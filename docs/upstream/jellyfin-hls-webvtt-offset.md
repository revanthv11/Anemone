# Draft: HLS WebVTT subtitles show 10 s late in remuxed fMP4 streams

A draft issue for [jellyfin/jellyfin](https://github.com/jellyfin/jellyfin/issues), not yet filed. Anemone no longer depends on it: since Phase 3d (P3b) it asks for text subtitles as files of their own and draws them itself (`DrawnSubtitles`). Before filing, check it against the server's current release and search for an existing issue.

---

**Title:** HLS WebVTT subtitles are 10 s late in fMP4 remuxes: `X-TIMESTAMP-MAP=MPEGTS:900000` but the video starts at 0

## Summary

When a video is remuxed (video and audio copied) to HLS with fragmented MP4 segments and text subtitles are delivered in the playlist (`SubtitleDeliveryMethod.Hls`), every subtitle segment maps its cues with `X-TIMESTAMP-MAP=MPEGTS:900000,LOCAL:00:00:00.000`. That says a cue time of 0 is media time 10 s (900000 at 90 kHz). The remuxed video's timestamps start at 0 (`-copyts -start_at_zero`), so a client that honours the map, as AVPlayer does, shows every cue 10 s late. Subtitles burned in by the same server are in time.

## Environment

- Server: Jellyfin 12.3.0 (Docker, `jellyfin/jellyfin`), jellyfin-ffmpeg as bundled.
- Client: AVPlayer on tvOS 26 (the Anemone app), Apple TV simulator.
- Device profile (the parts that matter):
  - `TranscodingProfile`: `Type=Video`, `Protocol=hls`, `Container=mp4`, `Context=Streaming`, `VideoCodec=hevc,h264`, `AudioCodec=aac,ac3,eac3,alac,flac`, `EnableSubtitlesInManifest=true`, `BreakOnNonKeyFrames=true`, `MinSegments=2`.
  - `SubtitleProfile`: `Format=vtt`, `Method=Hls`.
  - No direct-play profile for MKV, so an MKV is remuxed.

## Steps to reproduce

1. Add an MKV with H.264 video, AAC audio and an SRT track whose first cue is at 00:00:02 (our test file: 1280x720 H.264, AAC stereo, SubRip "English", 120 s).
2. Ask for PlaybackInfo with the profile above and `SubtitleStreamIndex` set to the SRT track. The server offers HLS that copies the video and audio (`TranscodingUrl` to `master.m3u8` with `SegmentContainer=mp4`; the server logs it as `FFmpeg.Remux-*.log`).
3. Play `master.m3u8` in AVPlayer and select the subtitles rendition.
4. The cue written for 00:00:02 shows at 00:00:12; every cue is 10 s late. With the subtitles burned in instead (`Method=Encode`), they're in time.

## Evidence

The master playlist lists the subtitles as an HLS rendition (API keys removed):

```
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English (SRT) - Default - SUBRIP",DEFAULT=YES,FORCED=NO,AUTOSELECT=YES,URI="ab853cbbe4041dcb42723a9220eca3ba/Subtitles/4/subtitles.m3u8?SegmentLength=30&ApiKey=x",LANGUAGE="eng"
```

The subtitle playlist asks for segments with copied timestamps and a time map:

```
#EXTM3U
#EXT-X-TARGETDURATION:30
#EXT-X-VERSION:3
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:30,
stream.vtt?CopyTimestamps=true&AddVttTimeMap=true&StartPositionTicks=0&EndPositionTicks=300000000&ApiKey=x
#EXTINF:30,
stream.vtt?CopyTimestamps=true&AddVttTimeMap=true&StartPositionTicks=300000000&EndPositionTicks=600000000&ApiKey=x
```

The first segment maps local time 0 to MPEG-TS time 900000 (10 s):

```
WEBVTT
X-TIMESTAMP-MAP=MPEGTS:900000,LOCAL:00:00:00.000

00:00:02.000 --> 00:00:06.000
English SRT · cue 1 · 00:02

00:00:08.000 --> 00:00:12.000
English SRT · cue 2 · 00:08
```

The remux that produces the video segments starts its timestamps at 0 (from the server's `FFmpeg.Remux-*.log`):

```
ffmpeg -analyzeduration 200M -probesize 1G -fflags +genpts -i file:".../Anemone Multi Track (2026).mkv"
  -map_metadata -1 -map_chapters -1 -threads 0 -map 0:0 -map 0:1 -map -0:s
  -codec:v:0 copy -bsf:v h264_mp4toannexb -start_at_zero -codec:a:0 copy
  -copyts -avoid_negative_ts disabled -max_muxing_queue_size 2048
  -f hls -max_delay 5000000 -hls_time 6 -hls_segment_type fmp4 ...
  -hls_playlist_type vod -hls_list_size 0 -hls_segment_options movflags=+frag_discont+skip_sidx ...
```

## Expected

The map matches the video segments' timeline: `MPEGTS:0` (or the first segment's actual start) for an fMP4 remux whose timestamps start at 0, or the time map left out when it isn't needed. Per RFC 8216 section 3.5, `X-TIMESTAMP-MAP` maps cue times to the media's presentation timestamps, so it should describe the timestamps the server actually wrote.

## Actual

The map is 900000 whatever the segment container and timestamp handling, so cues land 10 s after the media time they were written for.

## Notes

- Seen with every text track of the file (SRT, forced, SDH, and ASS converted to WebVTT).
- Burned-in subtitles (`Method=Encode`, PGS here) and the same SRT fetched whole from `/Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/Stream.srt` and drawn by the client against AVPlayer's clock are in time with the same remux (checked against the test pattern's own timestamp at the start, after a 30 s seek and after a new stream for another audio track), so the video's timeline is the one the cues were written for.
- 900000 looks like the offset for MPEG-TS segments, whose timestamps conventionally start at 10 s; it doesn't hold for fMP4 segments made with `-start_at_zero`.
- Client workaround (Anemone): a `SubtitleProfile` with `Method=External` for text formats, fetching the whole file and drawing it in the app.
