#!/usr/bin/env sh
set -eu

command -v ffmpeg >/dev/null 2>&1 || {
    echo "missing ffmpeg" >&2
    exit 1
}

command -v zig >/dev/null 2>&1 || {
    echo "missing zig" >&2
    exit 1
}

tmp_dir="${TMPDIR:-/tmp}/zig-player-smoke"
mkdir -p "$tmp_dir"

echo "building zig_player"
zig build

make_h264_aac_mp4() {
    ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i testsrc=size=320x180:rate=30 \
        -f lavfi -i sine=frequency=440:sample_rate=48000 \
        -t 1 -pix_fmt yuv420p \
        -c:v libx264 -c:a aac \
        "$tmp_dir/h264-aac.mp4"
}

make_h264_pcm_mov() {
    ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i testsrc=size=320x180:rate=30 \
        -f lavfi -i sine=frequency=440:sample_rate=48000 \
        -t 1 -pix_fmt yuv420p \
        -c:v libx264 -c:a pcm_s16le \
        "$tmp_dir/h264-pcm.mov"
}

make_vp9_opus_webm() {
    ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i testsrc=size=320x180:rate=30 \
        -f lavfi -i sine=frequency=440:sample_rate=48000 \
        -t 1 -pix_fmt yuv420p \
        -c:v libvpx-vp9 -c:a libopus \
        "$tmp_dir/vp9-opus.webm"
}

make_h264_opus_mkv() {
    ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i testsrc=size=320x180:rate=30 \
        -f lavfi -i sine=frequency=440:sample_rate=48000 \
        -t 1 -pix_fmt yuv420p \
        -c:v libx264 -c:a libopus \
        "$tmp_dir/h264-opus.mkv"
}

make_hevc_aac_mp4() {
    ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i testsrc=size=320x180:rate=30 \
        -f lavfi -i sine=frequency=440:sample_rate=48000 \
        -t 1 -pix_fmt yuv420p \
        -c:v libx265 -c:a aac \
        "$tmp_dir/hevc-aac.mp4"
}

make_h264_aac_5_1_mp4() {
    ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i testsrc=size=320x180:rate=30 \
        -f lavfi -i anullsrc=channel_layout=5.1:sample_rate=48000 \
        -t 1 -pix_fmt yuv420p \
        -c:v libx264 -c:a aac \
        "$tmp_dir/h264-aac-5-1.mp4"
}

run_case() {
    name="$1"
    path="$2"

    printf 'smoke: %s ... ' "$name"
    ./zig-out/bin/zig_player "$path" >/tmp/zig-player-smoke.log 2>&1 || {
        echo "fail"
        cat /tmp/zig-player-smoke.log
        exit 1
    }
    echo "pass"
}

make_h264_aac_mp4
make_h264_pcm_mov
make_vp9_opus_webm
make_h264_opus_mkv
make_hevc_aac_mp4
make_h264_aac_5_1_mp4

run_case "MP4 H264 AAC" "$tmp_dir/h264-aac.mp4"
run_case "MOV H264 PCM-S16" "$tmp_dir/h264-pcm.mov"
run_case "WebM VP9 Opus" "$tmp_dir/vp9-opus.webm"
run_case "MKV H264 Opus" "$tmp_dir/h264-opus.mkv"
run_case "MP4 HEVC AAC" "$tmp_dir/hevc-aac.mp4"
run_case "MP4 H264 AAC 5.1" "$tmp_dir/h264-aac-5-1.mp4"
