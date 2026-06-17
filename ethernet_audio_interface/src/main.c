// To run without sudo:
// sudo setcap "cap_sys_nice+ep cap_net_raw+ep" ./build/ethernet_audio_interface

// CPU frequency scaling
// sudo cpupower frequency-set -g performance

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
#include <time.h>
#include <sched.h>

#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/utils/ringbuffer.h>


#define IFACE_NAME           "enp0s20f0u2u4"
#define AUDIO_BUF_FRAMES     32
#define NUM_CHANNELS         12
#define SAMPLE_RATE          48000
#define RING_FRAMES          512
#define RING_SAMPLES         (RING_FRAMES * NUM_CHANNELS)
#define FRAME_BYTES          (NUM_CHANNELS * sizeof(int16_t))
#define RING_BYTES           (RING_FRAMES * FRAME_BYTES)
#define ETH_TX_PAYLOAD_BYTES 46
#define ETHERTYPE_TX         0xB588  // Local experimental
#define NODE_QUANTUM         128


static const uint8_t MAC_FPGA[6]      = {0x02, 0xDE, 0xAD, 0xBE, 0xEF, 0x67};
static const uint8_t MAC_BROADCAST[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};


// Ethernet TX packet
typedef struct {
    uint8_t  mac_dst[6];
    uint8_t  mac_src[6];
    uint16_t ethertype;
    uint8_t  payload[ETH_TX_PAYLOAD_BYTES];
} __attribute__((packed)) eth_tx_t;


// Global data
typedef struct {
    struct spa_ringbuffer   ring;
    int16_t                 ring_buf[RING_SAMPLES];

    struct pw_thread_loop  *pw_loop;
    struct pw_stream       *pw_stream;
   
    // For only eth_thread
    int              sock;
    eth_tx_t         eth_tx;
    struct sockaddr *tx_addr;
} shared_t;


static int8_t mac_addr_match(const uint8_t *mac1, const uint8_t *mac2) {
    for (uint8_t i = 0; i < 6; ++i) {
        if (mac1[i] != mac2[i]) {
            return 0;
        }
    }
    return 1;
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

    uint32_t requested_frames = pwb->requested ? (uint32_t)pwb->requested : AUDIO_BUF_FRAMES;
    uint32_t max_frames = d->maxsize / FRAME_BYTES;
    uint32_t n_frames = requested_frames < max_frames ? requested_frames : max_frames;
    uint32_t n_bytes = n_frames * FRAME_BYTES;

    int16_t *out = d->data;

    uint32_t read_idx;
    int32_t  avail_frames_signed = spa_ringbuffer_get_read_index(&s->ring, &read_idx);
    uint32_t avail_frames;
    if (avail_frames_signed > 0) {
        avail_frames = (uint32_t) avail_frames_signed;
    } else {
        avail_frames = 0;
    }

    if (avail_frames >= n_frames) {
        spa_ringbuffer_read_data(
            &s->ring,

            s->ring_buf,
            sizeof(s->ring_buf),
            (read_idx % RING_FRAMES) * FRAME_BYTES,

            out,
            n_bytes
        );
        spa_ringbuffer_read_update(&s->ring, read_idx + n_frames);
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
    d->chunk->stride = (int32_t)FRAME_BYTES;

    pw_stream_queue_buffer(s->pw_stream, pwb);
}


static const struct pw_stream_events stream_events = {
    PW_VERSION_STREAM_EVENTS,
    .process = on_process,
};


static int transmit_sp_offset(int sock, eth_tx_t *eth_tx, struct sockaddr *eth_addr, int16_t sample_period_offset) {
    eth_tx->payload[44] = (uint8_t) ((sample_period_offset >> 8) & 0x00FF);
    eth_tx->payload[45] = (uint8_t) (sample_period_offset & 0x00FF);
    size_t eth_tx_bytes   = sizeof(struct ethhdr) + ETH_TX_PAYLOAD_BYTES;
    size_t eth_addr_bytes = sizeof(struct sockaddr_ll);
    if (sendto(sock, eth_tx, eth_tx_bytes, 0, eth_addr, eth_addr_bytes) < 0) {
        perror("sendto");
        return 1;
    }
    //printf("Sent sample period offset: {0x%X, 0x%X}\n", eth_tx->payload[44], eth_tx->payload[45]);
    return 0;
}


static void *eth_thread(void *arg) {
    shared_t *s = (shared_t *)arg;
    uint8_t buf[ETH_FRAME_LEN];
    const size_t FRAME_LEN_EXPECTED = ETH_HLEN + AUDIO_BUF_FRAMES*FRAME_BYTES;
    
    int16_t audio_buf[AUDIO_BUF_FRAMES*NUM_CHANNELS];
    const size_t AUDIO_BUF_BYTES = sizeof(audio_buf);

    //struct timespec ts;
    //time_t current_t_s;
    //long   current_t_ns;
    //time_t prev_t_s = 0;
    //long   prev_t_ns = 0;
    //double elapsed_t_s;
    //double sample_rate_received;

    int16_t sample_period_offset;
    double  buffer_fill_error;
    double  buffer_fill_error_avg = 0;
    double  buffer_fill_error_P = 1./16.;
    double  buffer_fill_error_I = 1./16.;

    //uint32_t loop_counter = 0;

    while (1) {
        ssize_t n = recv(s->sock, buf, sizeof(buf), 0);
        if (n < 0) {
            perror("recv");
            break;
        }

        if ((size_t)n != FRAME_LEN_EXPECTED) {
            //fprintf(stderr, "Skipping frame with incorrect length (%zd bytes)\n", n);
            continue;
        }

        struct ethhdr *eth = (struct ethhdr *)buf;
        if (!mac_addr_match(eth->h_dest,   MAC_BROADCAST)) continue;
        if (!mac_addr_match(eth->h_source, MAC_FPGA))      continue;

        //clock_gettime(CLOCK_MONOTONIC, &ts);
        //current_t_s = ts.tv_sec;
        //current_t_ns = ts.tv_nsec;
        //if (prev_t_s != 0) {
        //    elapsed_t_s = ((double)(current_t_s - prev_t_s)) + 1.0e-9 * (current_t_ns - prev_t_ns);
        //    sample_rate_received = AUDIO_BUF_FRAMES / elapsed_t_s;
        //    if (sample_rate_received < 44.0e3 && sample_rate_received > 52.0e3) {
        //        printf("Anomalous sample rate received: %f\n", sample_rate_received);
        //    }
        //}

        uint8_t *payload = buf + ETH_HLEN;

        for (size_t i = 0; i < AUDIO_BUF_FRAMES*NUM_CHANNELS; ++i) {
            audio_buf[i] = (int16_t)((payload[2*i + 1] << 8) | payload[2*i]);
        }

        uint32_t write_idx;
        int32_t  filled_frames_signed = spa_ringbuffer_get_write_index(&s->ring, &write_idx);
        uint32_t filled_frames;
        if (filled_frames_signed > 0) {
            filled_frames = (uint32_t) filled_frames_signed;
        } else {
            filled_frames = 0;
        }

        if (filled_frames + AUDIO_BUF_FRAMES > RING_FRAMES) {
            fprintf(stderr, "Ring buffer overrun, dropping frame\n");
            continue;
        }

        spa_ringbuffer_write_data(
            &s->ring,

            // Ring buffer data pointer, size, and offset
            s->ring_buf,
            sizeof(s->ring_buf),
            (write_idx % RING_FRAMES) * FRAME_BYTES,

            // Source data pointer and size
            audio_buf,
            AUDIO_BUF_BYTES
        );
        spa_ringbuffer_write_update(&s->ring, write_idx + AUDIO_BUF_FRAMES);

        //buffer_fill_error = (double)filled_frames - RING_FRAMES/2.0;
        //buffer_fill_error_avg = 0.75*buffer_fill_error_avg + 0.25*buffer_fill_error;
        //if (buffer_fill_error <= 2*AUDIO_BUF_FRAMES && buffer_fill_error >= -2*AUDIO_BUF_FRAMES) {
        //    buffer_fill_error_P = 0;
        //} else {
        //    buffer_fill_error_P = 1./32.;
        //}
        //sample_period_offset = (int16_t) (
        //    buffer_fill_error_P * buffer_fill_error +
        //    buffer_fill_error_I * buffer_fill_error_avg
        //);
        //if (sample_period_offset > 32) {
        //    sample_period_offset = 32;
        //} else if (sample_period_offset < -32) {
        //    sample_period_offset = -32;
        //}
        
        buffer_fill_error = (double)filled_frames - RING_FRAMES/2.;
        if (buffer_fill_error >= -NODE_QUANTUM/2. && buffer_fill_error <= NODE_QUANTUM/2.) {
            buffer_fill_error = 0.;
        }
        buffer_fill_error_avg = 0.5*buffer_fill_error_avg + 0.5*buffer_fill_error;
        sample_period_offset = (int16_t) (
            buffer_fill_error_P * buffer_fill_error +
            buffer_fill_error_I * buffer_fill_error_avg
        );
        if (sample_period_offset > 32) {
            sample_period_offset = 32;
        } else if (sample_period_offset < -32) {
            sample_period_offset = -32;
        }

        //printf("Filled frames: %03d  |  Sample period offset: %03d\n", filled_frames, sample_period_offset);

        transmit_sp_offset(
            s->sock,
            &s->eth_tx,
            s->tx_addr,
            (int16_t) sample_period_offset
        );

        //printf(
        //    "Wrote Ethernet payload to ring buffer at index: %d (%d filled frames)\n",
        //    write_idx % RING_FRAMES,
        //    filled_frames
        //);

        //prev_t_s = current_t_s;
        //prev_t_ns = current_t_ns;
        //++loop_counter;
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

    // Get interface index from name
    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, IFACE_NAME, IFNAMSIZ - 1);
    if (ioctl(s.sock, SIOCGIFINDEX, &ifr) < 0) {
        perror("ioctl SIOCGIFINDEX");
        close(s.sock);
        return 1;
    }
    int if_index = ifr.ifr_ifindex;

    // Get sender MAC address
    if (ioctl(s.sock, SIOCGIFHWADDR, &ifr) < 0) {
        perror("ioctl SIOCGIFHWADDR");
        close(s.sock);
        return 1;
    }

    // Construct and bind sockaddr_ll for Ethernet receiver
    struct sockaddr_ll sll;
    memset(&sll, 0, sizeof(sll));
    sll.sll_family   = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex  = if_index;
    if (bind(s.sock, (struct sockaddr *)&sll, sizeof(sll)) < 0) {
        perror("bind");
        close(s.sock);
        return 1;
    }

    // Construct sockaddr_ll for Ethernet transmitter
    struct sockaddr_ll tx_addr;
    memset(&tx_addr, 0, sizeof(tx_addr));
    tx_addr.sll_family  = AF_PACKET;
    tx_addr.sll_ifindex = if_index;
    tx_addr.sll_halen   = ETH_ALEN;
    memcpy(tx_addr.sll_addr, MAC_FPGA, 6);
    s.tx_addr = (struct sockaddr *)&tx_addr;

    // Construct Ethernet TX frame
    memcpy(s.eth_tx.mac_dst, MAC_FPGA, 6);
    memcpy(s.eth_tx.mac_src, ifr.ifr_hwaddr.sa_data, 6);
    s.eth_tx.ethertype = ETHERTYPE_TX;
    memset(s.eth_tx.payload, 0, 44);  // Padding

    // Ethernet thread
    pthread_t eth_tid;
    pthread_create(&eth_tid, NULL, eth_thread, &s);
    struct sched_param param;
    param.sched_priority = 80; 
    if (pthread_setschedparam(eth_tid, SCHED_FIFO, &param) != 0) {
        perror("pthread_setschedparam failed");
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

    printf("Streaming audio...\n");

    pthread_join(eth_tid, NULL);

    pw_thread_loop_stop(s.pw_loop);
    pw_stream_destroy(s.pw_stream);
    pw_thread_loop_destroy(s.pw_loop);
    pw_deinit();
    close(s.sock);
    return 0;
}

