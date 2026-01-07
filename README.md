# SoundBite 🎵

**SoundBite** is a minimalist, glass-morphic YouTube Music player for macOS. It focuses on a clean aesthetic and bulletproof audio reliability, stripping away the clutter of the standard web interface to provide a native-feeling experience.

## Features ✨

* **Glass-Morphic Design**: A beautiful, translucent UI that blends seamlessly with your desktop.
* **Ad-Free Experience**: Custom logic to ensure uninterrupted playback.
* **Native Controls**: Media keys support and standard macOS window management.
* **Bulletproof Audio Engine**: Built on a custom-hardened WebKit implementation that solves common "silent audio" issues.

## The Audio Engine (Technical Deep Dive) 🛠️

SoundBite implements a robust set of overrides to ensure audio plays reliably 100% of the time, solving a common issue where "headless" WKWebViews on macOS get suspended or muted by YouTube's autoplay policies.

We achieved this via the "Triple-Lock" Strategy:

1. **Volume Police 👮‍♂️**: A custom JavaScript injection that actively monitors the HTML5 `<video>` element. If YouTube tries to auto-mute the volume (a common behavior on load), our script catches the `volumechange` event and instantly force-reverts it to 100%.
2. **Anti-Headless Measure (The 1x1 Pixel Fix) 👻**: macOS aggressively suspends `AudioContext` for WebViews that are hidden (0x0 size) to save battery. SoundBite renders the internal WebView at exactly **1x1 pixel** with `0.01` opacity. This makes it invisible to the user but "visible" to the operating system, keeping the audio engine alive.
3. **Identity Mirroring 🎭**: The player identifies itself with the exact User-Agent and configuration of a standard macOS Safari (Sonoma) session, enabling capabilities like `isElementFullscreenEnabled` and `allowsAirPlayForMediaPlayback`. This prevents YouTube from serving a limited "mobile" or "unsupported" player.

## Installation 📦

To build and run SoundBite yourself:

1. **Clone the repository**:

    ```bash
    git clone https://github.com/theaafofficial/SoundBite.git
    cd SoundBite
    ```

2. **Build the App**:
    We've included a helper script to compile the valid `.app` bundle:

    ```bash
    ./bundle_app.sh
    ```

3. **Run**:
    Open `SoundBite.app` in your finder or run:

    ```bash
    open SoundBite.app
    ```

## Contributing 🤝

Contributions are welcome! If you have ideas for visual improvements or engine tweaks:

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

Distributed under the MIT License.
