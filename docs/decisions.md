# Decisions

**D1 — Train on device with MLX Swift.** Inputs are 180-dim keypoint sequences
and the models are small; an M1 iPad can train them. Cloud notebooks are
optional, for reproducible baselines only.

**D2 — Keypoints, not video, leave the device.** Much smaller, and a landmark
sequence does not show the signer's face or surroundings.

**D3 — Keep the three-column NavigationSplitView and its sections.** The
redesign changes visual treatment, not information architecture.

**D4 — Dark-first UI.** Content is video with skeleton overlays and training
telemetry; long sessions.

**D5 — Background training via BGProcessingTask + checkpoints**, replacing the
silent-audio keep-alive before any distribution build.

**D6 — Future model arms need controls.** A connectome reservoir is only
reported alongside a degree-matched shuffled-graph control. Connectome source:
MaleCNS v1.0, HHMI Janelia FlyEM, CC-BY 4.0.
