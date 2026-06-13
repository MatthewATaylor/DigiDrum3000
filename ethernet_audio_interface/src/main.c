// To run without sudo:
// sudo setcap cap_net_raw+ep ./build/ethernet_audio_interface

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <linux/if_packet.h>
#include <linux/if_ether.h>
#include <sys/socket.h>
#include <sys/ioctl.h>

#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/utils/ringbuffer.h>


#define MAC_SRC         0x02DEADBEEF67ULL
#define MAC_DEST        0xFFFFFFFFFFFFULL
#define IFACE_NAME      "enp0s20f0u2u4"
#define AUDIO_BUF_SIZE  32
#define NUM_CHANNELS    12
#define SAMPLE_RATE     48000
#define RING_SAMPLES    4096
#define AUDIO_STRIDE    (NUM_CHANNELS * sizeof(int16_t))
#define RING_BYTES      (RING_SAMPLES * AUDIO_STRIDE)


// Data shared between threads
typedef struct {
    struct spa_ringbuffer   ring;
    int16_t                 ring_buf[RING_SAMPLES * NUM_CHANNELS];

    struct pw_thread_loop  *pw_loop;
    struct pw_stream       *pw_stream;
    
    int                     sock;
} shared_t;


static unsigned long long mac_addr_ptr_to_int(const unsigned char *mac_addr) {
    unsigned long long mac_addr_int = 0;
    for (uint8_t i = 0; i < ETH_ALEN; ++i)
        mac_addr_int |= ((unsigned long long)mac_addr[i]) << (8 * (ETH_ALEN-1-i));
    return mac_addr_int;
}


static void on_process(void *userdata) {
    shared_t *s = (shared_t *)userdata;

    struct pw_buffer *pwb = pw_stream_dequeue_buffer(s->pw_stream);
    if (!pwb) {
        pw_log_warn("Out of PipeWire buffers");
        return;
    }

    struct spa_data *d = &pwb->buffer->datas[0];
    if (!d->data) {
        pw_stream_queue_buffer(s->pw_stream, pwb);
        return;
    }

    uint32_t requested_frames = pwb->requested ? (uint32_t)pwb->requested : AUDIO_BUF_SIZE;
    uint32_t max_frames = d->maxsize / (NUM_CHANNELS * sizeof(int16_t));
    uint32_t n_frames = requested_frames < max_frames ? requested_frames : max_frames;
    uint32_t n_bytes = n_frames * NUM_CHANNELS * sizeof(int16_t);

    int16_t *out = d->data;

    uint32_t read_idx;
    int32_t  avail_bytes = spa_ringbuffer_get_read_index(&s->ring, &read_idx);
    uint32_t avail_frames;
    if (avail_bytes > 0) {
        avail_frames = (uint32_t)avail_bytes / (NUM_CHANNELS * sizeof(int16_t));
    } else {
        avail_frames = 0;
    }

    if (avail_frames >= n_frames) {
        spa_ringbuffer_read_data(
            &s->ring,

            s->ring_buf,
            sizeof(s->ring_buf),
            (read_idx % RING_SAMPLES) * AUDIO_STRIDE,

            out,
            n_bytes
        );
        spa_ringbuffer_read_update(&s->ring, read_idx + n_frames);
        printf("Read %d frames from ring buffer at index: %d\n", n_frames, read_idx);
    } else {
        // Underrun (fill with zeros)
        memset(out, 0, n_bytes);
        fprintf(
            stderr,
            "Ring buffer underrun (have %u frames, need %u)\n",
            avail_frames, n_frames
        );
    }

    d->chunk->offset = 0;
    d->chunk->size   = n_bytes;
    d->chunk->stride = (int32_t)AUDIO_STRIDE;

    pw_stream_queue_buffer(s->pw_stream, pwb);
}


static const struct pw_stream_events stream_events = {
    PW_VERSION_STREAM_EVENTS,
    .process = on_process,
};


static void *eth_thread(void *arg) {
    shared_t *s = (shared_t *)arg;
    uint8_t buf[ETH_FRAME_LEN];
    const size_t FRAME_LEN_EXPECTED = ETH_HLEN + 2*AUDIO_BUF_SIZE*NUM_CHANNELS;
    
    int16_t audio_buf[AUDIO_BUF_SIZE*NUM_CHANNELS];
    const size_t AUDIO_BUF_BYTES = sizeof(audio_buf);

    while (1) {
        ssize_t n = recv(s->sock, buf, sizeof(buf), 0);
        if (n < 0) {
            perror("recv");
            break;
        }

        if ((size_t)n != FRAME_LEN_EXPECTED) {
            fprintf(stderr, "Skipping frame with incorrect length (%zd bytes)\n", n);
            continue;
        }

        struct ethhdr *eth = (struct ethhdr *)buf;
        if (mac_addr_ptr_to_int(eth->h_dest)   != MAC_DEST) continue;
        if (mac_addr_ptr_to_int(eth->h_source) != MAC_SRC)  continue;

        uint8_t *payload = buf + ETH_HLEN;

        for (size_t i = 0; i < AUDIO_BUF_SIZE*NUM_CHANNELS; ++i) {
            audio_buf[i] = (int16_t)((payload[2*i + 1] << 8) | payload[2*i]);
        }

        uint32_t write_idx;
        int32_t  fill_level = spa_ringbuffer_get_write_index(&s->ring, &write_idx);
        if (fill_level > 0) {
            if ((size_t)fill_level + AUDIO_BUF_BYTES > sizeof(s->ring_buf)) {
                fprintf(stderr, "Ring buffer overrun, dropping frame\n");
                continue;
            }
        }

        spa_ringbuffer_write_data(
            &s->ring,

            // Ring buffer data pointer, size, and offset
            s->ring_buf,
            sizeof(s->ring_buf),
            (write_idx % RING_SAMPLES) * AUDIO_STRIDE,

            // Source data pointer and size
            audio_buf,
            AUDIO_BUF_BYTES
        );
        spa_ringbuffer_write_update(&s->ring, write_idx + AUDIO_BUF_SIZE);

        printf("Wrote Ethernet payload to ring buffer at index: %d\n", write_idx % RING_SAMPLES);
    }

    return 0;
}


int main(int argc, char *argv[]) {
    shared_t s;
    memset(&s, 0, sizeof(s));
    spa_ringbuffer_init(&s.ring);

    s.sock = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (s.sock < 0) {
        perror("socket");
        return 1;
    }

    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, IFACE_NAME, IFNAMSIZ - 1);
    if (ioctl(s.sock, SIOCGIFINDEX, &ifr) < 0) {
        perror("ioctl");
        close(s.sock);
        return 1;
    }

    struct sockaddr_ll sll;
    memset(&sll, 0, sizeof(sll));
    sll.sll_family   = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex  = ifr.ifr_ifindex;
    if (bind(s.sock, (struct sockaddr *)&sll, sizeof(sll)) < 0) {
        perror("bind");
        close(s.sock);
        return 1;
    }

    pw_init(&argc, &argv);

    s.pw_loop = pw_thread_loop_new("eth-audio-src", NULL);
    if (!s.pw_loop) {
        fprintf(stderr, "pw_thread_loop_new failed\n");
        return 1;
    }

    uint8_t pod_buf[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(pod_buf, sizeof(pod_buf));
    const struct spa_pod *params[1];
    params[0] = spa_format_audio_raw_build(
        &b,
        SPA_PARAM_EnumFormat,
        &SPA_AUDIO_INFO_RAW_INIT(
            .format   = SPA_AUDIO_FORMAT_S16,
            .rate     = SAMPLE_RATE,
            .channels = NUM_CHANNELS
        )
    );

    pw_thread_loop_lock(s.pw_loop);

    s.pw_stream = pw_stream_new_simple(
        pw_thread_loop_get_loop(s.pw_loop),
        "eth-audio-src",
        pw_properties_new(
            PW_KEY_MEDIA_TYPE,     "Audio",
            PW_KEY_MEDIA_CATEGORY, "Playback",
            PW_KEY_MEDIA_ROLE,     "Production",
            NULL
        ),
        &stream_events,
        &s
    );
    if (!s.pw_stream) {
        fprintf(stderr, "pw_stream_new_simple failed\n");
        return 1;
    }

    pw_stream_connect(
        s.pw_stream,
        PW_DIRECTION_OUTPUT,
        PW_ID_ANY,
        //PW_STREAM_FLAG_AUTOCONNECT |
        PW_STREAM_FLAG_MAP_BUFFERS |
        PW_STREAM_FLAG_RT_PROCESS,
        params,
        1
    );

    pw_thread_loop_unlock(s.pw_loop);
    pw_thread_loop_start(s.pw_loop);

    // Ethernet thread
    pthread_t eth_tid;
    pthread_create(&eth_tid, NULL, eth_thread, &s);

    printf("Streaming audio...\n");

    pthread_join(eth_tid, NULL);

    pw_thread_loop_stop(s.pw_loop);
    pw_stream_destroy(s.pw_stream);
    pw_thread_loop_destroy(s.pw_loop);
    pw_deinit();
    close(s.sock);
    return 0;
}

