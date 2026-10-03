# AutoShort2

AutoShort2 is an automated video repurposing pipeline built around OpenShorts, Gemini, Docker, GitHub Actions, and the YouTube Data API v3.

The project takes a long-form YouTube video, identifies strong moments using AI-assisted analysis, generates multiple vertical Shorts, creates publishing metadata, selects an appropriate YouTube category, and can automatically publish the resulting Shorts to YouTube.

## Overview

The pipeline is designed around the following flow:

```text
Long-form YouTube video
        |
        v
GitHub Actions: Test Clip Generation
        |
        v
OpenShorts backend
        |
        +--> Video download
        +--> Transcription
        +--> Content analysis
        +--> Clip scoring
        +--> Semantic event grouping
        +--> Diverse clip selection
        +--> Short generation
        |
        v
GitHub Actions artifact
        |
        v
GitHub Actions: Publish Shorts to YouTube
        |
        +--> Load OpenShorts metadata
        +--> Validate generated Shorts
        +--> Retrieve YouTube categories
        +--> Gemini category classification
        +--> YouTube OAuth authentication
        |
        v
Published YouTube Shorts
```

## Features

### AI-assisted clip selection

Candidate moments are evaluated using multiple signals rather than selecting timestamps randomly. The selection process considers:

- Viral potential
- Content importance
- Semantic event grouping
- Timeline coverage
- Setup and payoff completeness
- Clip duration
- Diversity across selected clips

The current shortlist combines viral and importance scores using:

```text
Combined Score = (Viral Score x 0.65) + (Importance Score x 0.35)
```

The selection process also limits repeated selections from the same semantic event group and favors clips that contain a complete narrative or payoff.

### Short generation

The generated clips are normalized into a predictable naming scheme:

```text
final-shorts/
├── short_01.mp4
├── short_02.mp4
├── short_03.mp4
└── ...
```

The generation artifact also contains:

```text
job-result.json
```

This metadata file is used by the publishing workflow to match each Short with its generated title, description, hook, and other metadata.

### Gemini-generated publishing metadata

Gemini is used to assist with publishing metadata, including:

- YouTube titles
- Descriptions
- Viral hooks
- YouTube category classification

Category selection is dynamic. The publisher first retrieves the currently assignable YouTube categories through the YouTube Data API and then asks Gemini to select the most appropriate category for each Short from that list.

### Automatic YouTube publishing

A successful generation run automatically triggers the publishing workflow through the GitHub Actions `workflow_run` event.

The publisher downloads the artifact produced by the exact generation run that triggered it and can upload either one selected Short or all generated Shorts.

Current automatic publishing configuration:

```text
Upload count: all
Privacy status: public
```

Manual publishing also supports:

```text
private
unlisted
public
```

## Architecture

```text
GitHub Actions
     |
     v
Docker Compose
     |
     +-------------------+
     |                   |
     v                   v
OpenShorts Backend    Remotion Renderer
     |
     +-- yt-dlp
     +-- Faster-Whisper
     +-- Gemini
     +-- Scene Detection
     +-- YOLO
     +-- Clip Selection
     |
     v
Generated Shorts
     |
     v
GitHub Actions Artifact
     |
     v
YouTube Publisher
     |
     +-- Gemini category classification
     +-- YouTube Data API
     +-- Google OAuth 2.0
     |
     v
YouTube Channel
```

## Technology Stack

| Technology | Purpose |
|---|---|
| Python | Core processing and automation |
| OpenShorts | AI-assisted short generation |
| Gemini | Content analysis and publishing metadata |
| Faster-Whisper | Speech transcription |
| yt-dlp | Video downloading |
| PyTorch | Machine learning inference |
| Ultralytics YOLO | Visual analysis |
| SceneDetect | Scene detection |
| Remotion | Video rendering |
| FastAPI | Backend API |
| Docker | Reproducible execution environment |
| GitHub Actions | Cloud workflow automation |
| YouTube Data API v3 | YouTube publishing and category lookup |
| Google OAuth 2.0 | YouTube authorization |

## Repository Structure

```text
AutoShort2/
├── .github/
│   └── workflows/
│       ├── test-clip.yml
│       └── youtube-publisher.yml
├── cloud/
├── dashboard/
├── remotion/
├── render-service/
├── tests/
├── active_speaker.py
├── app.py
├── clip_selection.py
├── scene_detection.py
├── subtitles.py
├── thumbnail.py
├── transcribe_backends.py
├── translate.py
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
├── .env.example
├── LICENSE
└── README.md
```

## GitHub Actions Workflows

### Test Clip Generation

Workflow:

```text
.github/workflows/test-clip.yml
```

This workflow is manually triggered with a YouTube video URL.

It performs the following steps:

1. Checks out the repository.
2. Creates the required output directories.
3. Starts the OpenShorts Docker services.
4. Waits for the backend readiness check.
5. Submits the supplied YouTube URL to the OpenShorts API.
6. Polls the processing job until it completes or fails.
7. Saves the returned job metadata as `job-result.json`.
8. Detects the generated final MP4 files.
9. Normalizes clip names to `short_01.mp4`, `short_02.mp4`, and so on.
10. Uploads the Shorts and metadata as a GitHub Actions artifact named `final-shorts`.

### Publish Shorts to YouTube

Workflow:

```text
.github/workflows/youtube-publisher.yml
```

This workflow supports both automatic and manual execution.

For automatic execution, it listens for a successful `Test Clip Generation` workflow on the `main` branch.

For manual execution, it accepts:

- `source_run_id`
- `upload_count`
- `privacy_status`

The publishing workflow validates the downloaded artifact before uploading anything. It checks that `job-result.json` exists, that Shorts are present, and that the number of generated videos matches the number of metadata records.

## Required GitHub Secrets

Add the following repository secrets under:

```text
Settings -> Secrets and variables -> Actions
```

### Gemini

```text
GEMINI_API_KEY
```

Used for AI-assisted clip analysis and YouTube category classification.

### YouTube source access

```text
YOUTUBE_COOKIES
```

Used by the generation workflow when YouTube authentication is required for source-video access.

### YouTube OAuth

```text
YOUTUBE_CLIENT_ID
YOUTUBE_CLIENT_SECRET
YOUTUBE_REFRESH_TOKEN
```

These credentials authorize the publishing workflow to upload videos to the configured YouTube channel.

### YouTube API key

```text
YOUTUBE_API_KEY
```

Used to retrieve assignable YouTube video categories dynamically through the YouTube Data API.

## Google Cloud Configuration

The YouTube publishing workflow requires a Google Cloud project with the YouTube Data API v3 enabled.

For OAuth-based publishing, create an OAuth 2.0 client and obtain a refresh token with the required YouTube upload scope.

The publishing workflow uses:

```text
https://www.googleapis.com/auth/youtube.upload
```

The API key is used separately for public category lookup.

## Running the Generator

Open the repository's GitHub Actions page:

```text
Actions -> Test Clip Generation -> Run workflow
```

Provide the source YouTube URL in `video_url` and start the workflow.

Example:

```text
https://www.youtube.com/watch?v=VIDEO_ID
```

After successful processing, the `final-shorts` artifact will contain the generated Shorts and the corresponding `job-result.json` metadata.

## Running the Publisher Manually

To publish an existing generation artifact without running the generator again:

```text
Actions -> Publish Shorts to YouTube -> Run workflow
```

Provide the source generation workflow run ID and select the desired upload mode.

Example:

```text
source_run_id: 37121475065
upload_count: all
privacy_status: private
```

Using `private` during testing is recommended before enabling public publishing.

## Publishing Validation

The publisher performs several checks before uploading:

- The source artifact exists.
- `job-result.json` exists.
- At least one `short_*.mp4` file exists.
- The number of Short files matches the number of metadata clips.
- Every selected Short receives exactly one valid YouTube category.
- Gemini cannot invent a category that is not returned by YouTube.
- Each selected Short has required title and description metadata.

If a validation check fails, publishing stops instead of attempting a potentially incorrect upload.

## Security

Never commit credentials, OAuth tokens, API keys, or YouTube cookies to the repository.

The following values must remain in GitHub Actions Secrets:

```text
GEMINI_API_KEY
YOUTUBE_COOKIES
YOUTUBE_CLIENT_ID
YOUTUBE_CLIENT_SECRET
YOUTUBE_REFRESH_TOKEN
YOUTUBE_API_KEY
```

## Current Limitations

### OAuth testing mode

The current Google OAuth application is configured in testing mode. Google testing-mode refresh tokens are subject to expiration and therefore are not yet a permanent unattended-production authentication solution.

For long-term unattended operation, the Google OAuth configuration should be moved to an appropriate production setup and the authorization flow should be maintained accordingly.

### YouTube upload limits

YouTube can impose channel-level upload limits. When those limits are reached, the YouTube API may return an error such as:

```text
uploadLimitExceeded
```

This is a YouTube-side restriction and is independent of the clip generation and metadata pipeline.

### Processing time

Processing time depends on the input video length, transcription, AI analysis, clip rendering, and the GitHub Actions runner. Longer source videos can take substantially longer to complete.

## Roadmap

- [x] AI-assisted clip generation
- [x] Viral scoring
- [x] Importance scoring
- [x] Semantic event grouping
- [x] Diversity-aware clip selection
- [x] Setup and payoff-oriented clip selection
- [x] Normalized Short numbering
- [x] GitHub Actions generation workflow
- [x] Artifact-based publishing
- [x] YouTube OAuth upload
- [x] Dynamic YouTube category selection
- [x] Automatic `workflow_run` publishing
- [x] Multi-Short publishing
- [ ] Production-ready unattended OAuth
- [ ] Scheduled daily processing
- [ ] Automatic source-video discovery
- [ ] Upload retry and recovery queue
- [ ] Publishing analytics
- [ ] Multi-channel support

## Contributing

Contributions, bug reports, suggestions, and pull requests are welcome.

Create a feature branch before making changes:

```bash
git checkout -b feature/your-feature
```

Test your changes before opening a pull request.

## Acknowledgements

AutoShort2 builds on the OpenShorts project and extends it with an automated GitHub Actions publishing workflow.

The project also uses and integrates open-source technologies including:

- OpenShorts
- Faster-Whisper
- yt-dlp
- PyTorch
- Ultralytics
- SceneDetect
- Remotion
- Google Gemini
- YouTube Data API v3


