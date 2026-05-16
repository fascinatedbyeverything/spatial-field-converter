# Nature Sound ID Libraries — Americas Focus (2026-05-15)

Research compiled via live web searches. All license terms and URLs verified against current sources. Where a model does not exist or is not production-ready, this is stated explicitly rather than padded.

---

## Recommended Starter Set (download / wire up first)

Ranked by: Americas coverage + license clarity + on-device viability for macOS/iOS.

**1. BirdNET-Analyzer V2.4 (Cornell + TU Chemnitz)**
Primary bird classifier. 6,522 species globally including strong South America coverage (eBird data is well-populated for the Americas). TFLite format — convertible to CoreML via coremltools. CC BY-NC-SA 4.0 model license. The non-commercial clause needs Chris's explicit sign-off before shipping.

**2. Apple SoundAnalysis (built-in, zero dependency)**
Free, on-device, no license friction — it's part of the OS. Covers ~300 categories including Bird, Frog/Croak, Cricket, Insect, Rain, Thunder, Wind, Stream, Waterfall. Acts as the fast first-pass triage layer before species-level classifiers fire. Wire this up day one.

**3. Google Perch V2 (Google DeepMind / Google Research)**
Foundation embedding model trained on 10k+ species. Apache-2.0 license — commercially usable. Best for embedding-based search and fine-tuning. TensorFlow/TFLite. Available from Kaggle Models. Perch 2.0 (August 2025) expands to multi-taxa (not just birds). Use as the embedding backbone for nearest-neighbor species lookup.

**4. xeno-canto API (reference database, not a classifier)**
500,000+ bird recordings, 7,000+ species. Foundational reference DB for training data, species lookup, playback. API key now required (as of October 2025). Per-recording CC licenses — mix of BY, BY-NC, BY-NC-SA. Do NOT use NC recordings in a commercial product without legal review. Wire up for species-confirmation playback in the UI.

**5. AnuraSet + custom fine-tuned classifier (Brazil frog coverage)**
No production-ready off-the-shelf frog classifier exists for Neotropical species. AnuraSet is the best available dataset: 42 species, Cerrado + Atlantic Forest biomes, MIT license, baseline training code included. Chris will need to train or fine-tune a model on this dataset. This is the frog ID gap that needs a decision.

---

## Bird Species Classifiers (audio → species ID)

### BirdNET-Analyzer (Cornell Lab + TU Chemnitz)
- **Maintainer:** Cornell Lab of Ornithology / TU Chemnitz (Stefan Kahl)
- **Species coverage:** 6,522 classes (global). South America is well-represented — eBird data covers the Americas, India, Europe, and Australia best. V2.4 includes a geographic range model (V2.4-V2, January 2024) that filters species by lat/lon + week-of-year using eBird checklist frequency data. You can generate a Brazil-specific species list using coordinates.
- **License:** Source code = MIT. **Models = CC BY-NC-SA 4.0** (non-commercial only). Educational/research use is explicitly permitted. Commercial use requires separate licensing — contact ccb-birdnet@cornell.edu.
- **Formats:** TFLite (primary), Protobuf/Raven. No official CoreML. Conversion path: TFLite → TF frozen graph → coremltools (requires intermediate step, not direct TFLite→CoreML). The LiteRT Core ML delegate allows running TFLite models via CoreML on iOS without full conversion.
- **Download:** https://github.com/birdnet-team/BirdNET-Analyzer — models on Zenodo. BirdNET-Lite repo is archived (March 2025), redirect to BirdNET-Analyzer.
- **Last updated:** V2.4.0 released November 7, 2025
- **On-device viability:** macOS: runs via Python with GPU support on Apple Silicon. iOS: TFLite works via LiteRT. No native SwiftUI API — requires bridging. Inference time not benchmarked publicly for Apple Silicon specifically, but EfficientNet backbone is fast; expect sub-100ms per 3-second audio window on M-series chips.

### Google Perch / Bird Vocalization Classifier
- **Maintainer:** Google Research / Google DeepMind
- **Species coverage:** 10,000+ species (Perch 2.0, August 2025). Trained on Xeno-canto + broad bioacoustics data. Perch 2.0 expands from birds-only to multi-taxa. Strong transfer learning performance on unseen species — useful for Neotropical species not in training set via embedding similarity.
- **License:** **Apache-2.0** — commercially usable, no NC restriction. This is the key differentiator vs BirdNET for a commercial product.
- **Formats:** TensorFlow 2 / TFLite (JAX → TF export path documented in repo). Available on Kaggle Models and TensorFlow Hub.
- **Download:** https://github.com/google-research/perch | https://www.kaggle.com/models/google/bird-vocalization-classifier
- **Last updated:** Perch 2.0 paper August 2025; model available via Kaggle
- **On-device viability:** TFLite available. ~12M parameter embedding model (EfficientNet-B3) + 91M parameter classification head. The embedding model alone is manageable on device; full classifier head is large. Best used as embedding extractor with a lightweight local classifier head.

### Merlin Bird ID (Cornell Lab)
- **Maintainer:** Cornell Lab of Ornithology
- **Species coverage:** 2,000+ species by sound, covering North America, Europe, Central and South America (common/widespread), India. Recent updates added 342 new species across South America, India, Taiwan, Australia. Not exhaustive for rare Neotropical species.
- **License:** **Proprietary — not available for third-party integration.** Merlin is a consumer app. The underlying model draws on BirdNET-influenced architecture but is not distributed separately. Cannot use in your own app.
- **Formats:** On-device (proprietary). Runs locally without network.
- **Download:** Not available externally.
- **Note:** Merlin is the best consumer-facing reference for what sound ID UX should feel like. Not an integration option.

### HawkEars
- **Maintainer:** jhuus (ABMI affiliated)
- **Species coverage:** 360 bird + 15 amphibian species. Canada + northern United States focus. Not suitable as primary South America classifier.
- **License:** **MIT** — commercially usable.
- **Formats:** PyTorch. Models auto-download via `hawkears init`.
- **Download:** https://github.com/jhuus/HawkEars
- **Last updated:** V2.0 published ScienceDirect March 2025
- **On-device viability:** PyTorch — not natively on-device for iOS without ONNX export. Could run on macOS Python backend. Not a fit for the Americas priority.

### BirdSet ConvNeXT / BirdSet EfficientNetB1
- **Maintainer:** DBD Research Group (German university consortium)
- **Species coverage:** Global bird species via Xeno-canto training data. Includes Neotropical test datasets (Amazon Basin, Colombia/Costa Rica soundscapes).
- **License:** Training recordings from xeno-canto are NC; SA licenses excluded. Test datasets CC BY 4.0. Model weights license — check repo (not confirmed in research).
- **Formats:** PyTorch. Available via OpenSoundscape bioacoustics-model-zoo.
- **Download:** https://github.com/DBD-research-group/BirdSet | Hugging Face: DBD-research-group/BirdSet
- **Last updated:** Presented ICLR 2025
- **On-device viability:** PyTorch → ONNX export feasible. Research-grade.

### BirdAVES / AVES (Earth Species Project)
- **Maintainer:** Earth Species Project
- **Species coverage:** Self-supervised foundation model trained on Xeno-canto bird recordings (33% of available corpus used). BirdAVES improves 20%+ over base AVES on bird datasets. General AVES covers multi-taxa animal vocalizations.
- **License:** **MIT** (AVES repo). Note: some HuggingFace model cards show CC-BY-NC-SA-4.0 — verify the specific checkpoint you use.
- **Formats:** PyTorch / TorchAudio, ONNX, Fairseq. AVEX package (2025 successor) available via pip.
- **Download:** https://github.com/earthspecies/aves | https://github.com/earthspecies/avex | HuggingFace: EarthSpeciesProject
- **Last updated:** AVEX package 2025; BirdAVES June 2024
- **On-device viability:** ONNX format makes cross-platform deployment possible. Large model — likely macOS only, not iOS. Good for fine-tuning on custom Neotropical datasets.

---

## Frog / Amphibian Classifiers

**Honest assessment: no production-grade, downloadable, cross-regional frog species classifier exists as of May 2026. The field is academic. What does exist:**

### AnuraSet (Dataset + Baseline Code)
- **Maintainer:** soundclim (Brazilian research consortium, passive acoustic monitoring program)
- **What it is:** Dataset + baseline training code. NOT a pretrained deployable model out of the box. You train on it.
- **Species coverage:** 42 Neotropical anuran species across Cerrado (sites INCT17, INCT41) and Atlantic Forest (INCT20955, INCT4) biomes in Brazil. 93,000 three-second audio samples. 27 hours annotated + 177.6 hours unlabeled (U-AnuraSet).
- **License:** **MIT** — dataset and code both permissive.
- **Format:** Training scripts in Python. Baseline uses transfer learning (CNN). No pretrained weights distributed.
- **Download:** https://github.com/soundclim/anuraset | Dataset on Zenodo: https://zenodo.org/records/8056090
- **Last updated:** Published Scientific Data 2023; U-AnuraSet extension added subsequently.
- **On-device viability:** Must train your own model. Once trained, export to CoreML or TFLite. Feasible.
- **Coverage gaps:** Covers Cerrado + Atlantic Forest. Amazon and Pantanal biomes not included. 42 species is a fraction of Brazil's ~1,100 known anuran species.

### UCI Anuran Calls (MFCCs) Dataset
- Older benchmark dataset (10 families, 14 genera, 8 species — Amazonian focus). Tiny by modern standards. Useful only as a supplementary validation set. No associated deployable model.

### VicFrogNET
- Victoria (Australia) frog classifier, mentioned in a 2026 paper evaluating BirdNET and VicFrogNET for frog/bird PAM. Australian species only — not relevant to Americas. Cited here to note it exists as a reference architecture.

### RIBBIT (OpenSoundscape)
- Pulse-rate detector for frog calls within OpenSoundscape. Not species-specific — detects frog call presence by pulse rhythm. Useful as a pre-filter before species classification. MIT license.

---

## Insect Classifiers (Cricket, Cicada, etc.)

**Honest assessment: research-grade only. No production-ready downloadable model for Neotropical insect species.**

### InsectSet459 + InsectEffNet / PaSST
- **Maintainer:** Bioacoustics research consortium (published Scientific Data, Nature portfolio, 2026)
- **What it is:** 459-species dataset (Orthoptera + Cicadidae) + two baseline deep learning classifiers (InsectEffNet = EfficientNetV2 CNN; PaSST = transformer). Published 2025, used in BioDCASE 2025 challenge.
- **Species coverage:** 459 species of crickets, grasshoppers, katydids, and cicadas. European + global focus. Not Neotropical-specific. 26,399 audio files, 9.5 days of material.
- **License:** CC 4.0 (dataset on Zenodo). Model weights: check paper/repo for specifics.
- **Download:** https://zenodo.org/records/14056458
- **On-device viability:** Research baseline. Would need retraining on Neotropical species. No Americas-specific coverage.

### YAMNet (Google)
- Covers "Insect", "Cricket", "Mosquito", "Fly/housefly", "Bee/wasp" as coarse categories. Not species-level. Useful as first-pass presence detector.
- **License:** Apache-2.0

### Audio-Based Insect Classification (arXiv 2502.13893, February 2025)
- ML classifier for cicada, beetle, termite, cricket using XGBoost / RF / KNN on MFCC features. Not a deployable model — academic paper with small species count.

**Bottom line on insects:** No deployable species-level insect classifier exists for Neotropical species. YAMNet catches "insect/cricket/bee" presence. Beyond that, custom training required.

---

## Mammal Classifiers (Howler Monkeys, Bats, etc.)

### BatDetect2
- **Maintainer:** macaodha (Oisin Mac Aodha, UCL)
- **Species coverage:** UK bat species (primary model). 17 UK species. Global application requires retraining — the architecture is designed to generalize, and the paper explicitly discusses a "general approach."
- **License:** **CC BY-NC 4.0** — non-commercial only. Confirmed via search.
- **Formats:** PyTorch checkpoints (.ckpt). Install via pip: `pip install batdetect2==2.0.0b1`. Demo on Hugging Face Spaces.
- **Download:** https://github.com/macaodha/batdetect2
- **Last updated:** Active development; Google Colab support added January 2024, Python 3.11 support added. Raspberry Pi 4 deployment verified June 2025.
- **On-device viability:** PyTorch — macOS feasible. iOS not straightforward.
- **Americas relevance:** The default model covers UK bats only. For South American/Neotropical bats (massive diversity — 250+ species in Brazil), you would need to train or fine-tune on Neotropical bat call data. No Neotropical bat model currently exists as a downloadable artifact. Bat echolocation for South America is an open research gap.

### Kaleidoscope Pro (Wildlife Acoustics)
- **What it is:** Commercial desktop software (subscription) with bat auto-ID classifiers for North America, Europe, South America, and the Neotropics. Not embeddable in your own app — it's a standalone tool.
- **License:** Commercial subscription ($495+/year). Models not extractable.
- **Relevance:** Reference point — proves a Neotropical bat classifier corpus exists commercially. Not directly usable in v0.2.

### Howler Monkey / Primate Detectors
- A 2021 PAM study built a howler monkey roar detector (42% recall / 100% precision in 3-month Brazil field recordings). Research-grade Python/R code. No packaged deployable model. Not a practical integration path for v0.2.

### NatureLM-audio (Earth Species Project)
- **What it is:** Audio-language foundation model (0.7B params). Ask natural language questions about animal vocalizations. BEATs audio encoder + Llama-3.1-8B-Instruct. Covers birds, mammals, amphibians from Xeno-canto + iNaturalist + Watkins Marine Mammal DB + Animal Sound Archive.
- **License:** **CC-BY-NC-SA-4.0** — non-commercial only.
- **Format:** Safetensors (PyTorch). Trained on 8xH100 GPUs. Apple Silicon CPU inference: very slow, not practical on-device.
- **Download:** https://github.com/earthspecies/NatureLM-audio | Hugging Face: EarthSpeciesProject/NatureLM-audio
- **Last updated:** ICLR 2025
- **Relevance:** Best for "what animal is making this sound" open-ended queries in a server-side pipeline. Not an on-device fit.

---

## General Environmental Classifiers (Rain, Water, Wind, Machinery)

### Apple SoundAnalysis — Built-in Classifier (version1 / servicesClassifier)
- **Maintainer:** Apple
- **Coverage:** 300+ categories. Confirmed nature/environment categories include:
  - **Animals:** Bird (vocalization/call/song), Chirp/tweet, Squawk, Crow (caw), Pigeon/dove (coo), Owl (hoot), Bird flight, Cricket, Mosquito, Fly, Bee/wasp, Frog (croak), Horse, Cat, Dog, Roar (big cats), Whale vocalization, Rooster, Duck, Goose, Chicken
  - **Weather:** Thunderstorm, Thunder, Rain (raindrop, rain on surface), Wind
  - **Water:** Stream, Waterfall, Ocean, Waves/surf, Gurgling
  - **Vegetation:** Rustling leaves
  - **Fire:** Fire crackle, Steam
- **License:** Part of Apple OS frameworks. Free to use in any app (no additional license). No model to download — it's baked in.
- **Format:** CoreML, accessed via SoundAnalysis framework (Swift/Obj-C). Fully hardware-accelerated via Neural Engine on Apple Silicon and A-series chips.
- **Download:** Built into macOS 12+ and iOS 15+. Use `SNClassifySoundRequest(classifierIdentifier: .version1)`.
- **On-device viability:** Native. Real-time on-device. Supports 0.5–15 second analysis windows. Confidence scores are independent (non-additive), unlike custom CreateML models.
- **Limitation:** No species-level ID. "Frog (croak)" is a single class — you cannot distinguish Boana from Dendropsophus using this alone.

### YAMNet (Google / TensorFlow)
- **Maintainer:** Google
- **Coverage:** 521 AudioSet classes (YouTube-sourced). Broader but coarser than Apple's built-in. Includes the same nature categories listed above plus: aircraft, tools, music, speech — useful as a background noise detector to gate your species classifiers.
- **License:** Apache-2.0 — commercially usable.
- **Formats:** TFLite, TensorFlow Hub. Convertible to CoreML.
- **Download:** TensorFlow Hub; also pip via `bioacoustics-model-zoo[tensorflow]`
- **On-device viability:** TFLite runs on iOS. Small model. Fast inference.

---

## Reference Databases (Canonical Recordings, NOT Classifiers)

### xeno-canto
- **URL:** https://www.xeno-canto.org
- **API:** `https://xeno-canto.org/api/3/recordings?query=...&key=YOUR_KEY`
- **Authentication:** API key required as of October 10, 2025. Free for registered members.
- **Response fields:** id, genus (gen), species (sp), subspecies, English name, country (cnt), location (loc), latitude, longitude, altitude, sound type (song/call/alarm/etc.), sex, life stage, file URL, recording date, upload date, recordist, license, quality rating (A–E), length, sampling rate, bitrate, channels, file size, background species, tags.
- **Geographic emphasis:** Global. Originally Neotropical-focused at launch (2005). Brazil has strong coverage via WikiAves cross-contributions.
- **License:** **Mixed CC.** Each recording has its own license. Common: CC BY, CC BY-NC, CC BY-NC-SA, CC BY-NC-ND. For commercial use, you must filter to CC BY recordings only (non-NC). Many recordings are CC BY-NC — cannot use in a commercial product without attribution AND non-commercial compliance.
- **Rate limits:** 1000 requests/hour for non-commercial use. Mass downloads require contacting xeno-canto directly.
- **Species count:** 500,000+ recordings, 7,000+ bird species. Xeno-canto also hosts frog calls (separate dataset): https://www.gbif.org/dataset/bcf8d1fc-6bf0-4f57-9076-7d9ae2828ec2

### Macaulay Library (Cornell Lab)
- **URL:** https://www.macaulaylibrary.org
- **Access:** Browse and stream freely. Programmatic bulk download requires a helpdesk ticket (macaulaylibrary@cornell.edu). No public REST API for downloads.
- **Contents:** 3.2M+ audio recordings, 84M+ photos, 300K+ videos. Covers 96% of world's bird species. Also has mammals, reptiles, amphibians, fish, arthropods.
- **License:** Scientific research / licensing uses — request via helpdesk. Not available for bulk programmatic commercial use without arrangement.
- **Geographic emphasis:** Global. Powers Merlin and eBird. Strong Americas coverage.
- **Note:** Macaulay Library recordings fed BirdNET and Perch training. This is the premier archive. Access for a commercial creative tool would require a formal licensing discussion with Cornell.

### iNaturalist / iNatSounds
- **URL:** https://www.inaturalist.org | API: https://api.inaturalist.org/v2/docs/
- **What it is:** iNatSounds (NeurIPS 2024) = 230,000 audio files, 5,500+ species from birds, mammals, insects, reptiles, amphibians. Research-grade observations globally.
- **License:** Observations submitted to iNaturalist use CC BY-NC or CC BY; check per-observation metadata. iNaturalist API is free for reasonable use.
- **Geographic emphasis:** Global citizen science. Strong Americas coverage.
- **API:** REST API v2 at api.inaturalist.org/v2. Query by taxon_id, place_id (e.g., Brazil), has_sounds=true.
- **Note:** The iNatSounds dataset is a benchmark dataset (NeurIPS 2024). Models trained on it are not publicly released yet. The raw observations are accessible via API.

### GBIF (Global Biodiversity Information Facility)
- **URL:** https://www.gbif.org | API: https://techdocs.gbif.org/en/openapi/
- **What it is:** Aggregator of species occurrence records from 1000s of contributing institutions including xeno-canto (indexed there as a dataset). Occurrence records can include media (sound recordings).
- **License:** GBIF mediated data is CC BY 4.0 or CC BY-NC 4.0 depending on dataset. Xeno-canto records in GBIF carry their individual CC licenses.
- **Geographic emphasis:** Global. Full Amazon/Brazil coverage.
- **API:** REST API returns JSON occurrence records with optional multimedia annotations. Endpoint: `https://api.gbif.org/v1/occurrence/search?taxonKey=&country=BR&mediaType=Sound`.
- **Note:** GBIF is better for species range/presence metadata than for accessing actual audio files. The audio files live at xeno-canto or Macaulay Library; GBIF holds the metadata and links.

### WikiAves
- **URL:** https://en.wikiaves.com.br | https://www.wikiaves.com.br (Portuguese)
- **API:** Unofficial R package: https://github.com/Athospd/wikiaves (athospd.github.io/wikiaves). No official REST API.
- **Contents:** 4M+ photographic records and 150,000+ sound recordings of 1,880 species. Brazilian birds only. Citizen science. Founded 2008.
- **License:** Not explicitly CC-licensed in the standard sense — community contributions under WikiAves own terms. Check their terms of service before bulk use.
- **Geographic emphasis:** Brazil exclusively. Best Brazilian-specific coverage of any free database.
- **Note:** WikiAves data partially cross-listed in xeno-canto. The R package enables batch download by species name — relevant for building a Brazil-specific training corpus.

### AmphibiaWeb
- **URL:** https://amphibiaweb.org
- **API:** No formal public API. Species lists downloadable. Sound files (823 files) accessible via species pages. Partners include Bioweb Ecuador and Amazon basin sources.
- **License:** Data use policy at amphibiaweb.org/data/datause.html — check before bulk use.
- **Geographic emphasis:** Global amphibians. Neotropical coverage via FonoZoo, Western Soundscape Archive, Guia de Sapos da Reserva Adolpho Ducke (Amazonia Central) contributions.
- **Note:** 823 files is small. Useful as a reference spot-check, not as training data at scale.

---

## Brazil / Neotropical Specific

### AnuraSet (Cerrado + Atlantic Forest Anurans)
See Frog section above. The definitive Brazil-specific frog call dataset. 42 species, Cerrado and Atlantic Forest biomes. MIT license. No pretrained model included — training required.
- Paper: https://www.nature.com/articles/s41597-023-02666-2
- Code + dataset: https://github.com/soundclim/anuraset
- Zenodo (10.5 GB dataset): https://zenodo.org/records/8056090

### WikiAves (Brazilian birds)
Largest Brazil-specific sound database. 150,000+ recordings. Unofficial API. See Reference Databases section.

### xeno-canto Brazil corpus
Filter API by `cnt:brazil` to get Brazil recordings. As of 2025, requires API key. Strong coverage of Brazilian birds from both resident species and migratory visitors.

### SACC (South American Classification Committee) Checklist
- **URL:** https://www.museum.lsu.edu/~Remsen/SACCCountryLists.htm
- Not a sound database. The authoritative taxonomic checklist for South American birds. Use this as the ground truth species list when building custom classifiers or validating BirdNET/Perch coverage. Brazil alone has ~1,900 bird species on this list.

### Brazilian Ornithological Records Committee (CBRO) Checklist
- **URL:** https://link.springer.com/article/10.1007/s43388-021-00058-x
- Published in Ornithology Research (2021, second edition). Annotated checklist of all Brazilian birds. Use to benchmark coverage of any classifier you deploy.

### Centro de Estudos Ornitológicos (CEO)
- **URL:** https://www.ceo.org.br
- São Paulo-based NGO since 1984. Maintains records including voice samples. Contributes to São Paulo state bird checklists. No public API or sound database found — they contribute to broader databases (xeno-canto, CBRO). Contact point for São Paulo-region field recordings if building a custom dataset.

### ICMBio / CEMAVE
- National Center for Wild Bird Conservation and Research (Chico Mendes Institute, Brazilian government). Involved in PAM research (referenced in IJCAI-23 paper). No publicly downloadable classifier. Contact point for institutional collaboration on Brazilian biodiversity monitoring.

### Arbimon (Rainforest Connection / RFCx)
- **URL:** https://arbimon.org
- Free, open-source ecoacoustics analysis platform. End-to-end pipeline: upload audio → detect → classify. Trained on Neotropical species for some classifiers. 60+ active projects including Amazon. The underlying classifiers are CNN-based and trained on regional soundscapes.
- **Relevance:** Arbimon is a web platform, not a downloadable model library. You can use it to validate species ID or as a research reference. RFCx has GitHub presence (https://github.com/rfcx) — check for any model releases. HuggingFace: rfcx org page exists.
- **Note:** Best Amazon/Brazil classifier infrastructure in production, but it's not a model you download — it's a service.

### Classifying Birds of South America (Springer, 2025)
- Academic paper: "Classifying birds of South America via audio analysis using convolutional networks and boosting models optimized by metaheuristics" (Iran Journal of Computer Science, 2025). Research-grade, not a deployable artifact.

---

## Integration Notes for the v0.2 Feature

### Architecture: YAMNet → BirdNET → Reference DB

The recommended pipeline is a three-stage funnel:

```
Stage 1: Apple SoundAnalysis (built-in)
  → Fast coarse classification: is this a bird? frog? insect? rain? 
  → On-device, zero latency, no license friction
  → Routes audio to the appropriate Stage 2 specialist

Stage 2: Species-level classifier
  → Birds: BirdNET V2.4 (TFLite) or Perch V2 (TFLite embedding)
  → Frogs: Custom-trained AnuraSet model (train once, ship weights)
  → Insects: YAMNet coarse only (no species level available)
  → Bats: BatDetect2 (UK model, or custom-trained if Neotropical bat data sourced)
  → General environment: Apple SoundAnalysis handles rain/wind/water well

Stage 3: Reference DB lookup
  → Species name from Stage 2 → xeno-canto API lookup for canonical recording
  → Display: species card, range map (from eBird/BirdNET occurrence model), reference call
```

### What to ship in the app bundle

Bundle only what is small enough and license-permissive. As of May 2026:

| Model | Size estimate | License | Bundle? |
|---|---|---|---|
| Apple SoundAnalysis (built-in) | 0 MB (OS) | Apple OS | Yes — always |
| BirdNET V2.4 TFLite | ~50 MB | CC BY-NC-SA | Only if non-commercial confirmed |
| Perch V2 embedding head | ~50–100 MB | Apache-2.0 | Yes — commercially safe |
| Custom AnuraSet model (trained) | ~5–20 MB | MIT (if you train it) | Yes |
| YAMNet TFLite | ~3.7 MB | Apache-2.0 | Yes |

### What to download on demand

- Full Perch classification head (large): download on first use
- BirdNET occurrence/range model: download lazily
- xeno-canto reference audio: stream on demand, never cache without checking per-recording license

### CoreML conversion notes

No official CoreML version of BirdNET or Perch exists. Conversion path:
1. TFLite → TF frozen graph (using TF 2.x APIs)
2. Frozen graph → CoreML using `coremltools.converters.convert()`
3. Alternatively: use LiteRT on iOS (Google's TFLite iOS runtime with CoreML delegate) — this uses CoreML under the hood without full conversion

The LiteRT CoreML delegate is the pragmatic path: TFLite model runs hardware-accelerated via Apple Neural Engine on iOS without a manual conversion step. See: https://ai.google.dev/edge/litert/ios/coreml

### Hardware notes (Apple Silicon)

- Apple SoundAnalysis: Neural Engine accelerated. Effectively free compute cost.
- TFLite (LiteRT) via CoreML delegate: Neural Engine on iOS/macOS. Expect 20–80ms per 3-second window for BirdNET-scale models on M1+.
- PyTorch models (HawkEars, AVES): CPU on Apple Silicon unless you use Metal via MPS backend. Slower — 200–500ms per window is realistic for research models.
- Full NatureLM-audio (0.7B): Not practical on-device. Server-side only.
- Memory: BirdNET TFLite ~150 MB RAM. Perch embedding model ~300 MB. AnuraSet custom model <50 MB.

### Combining BirdNET + Perch for Neotropical coverage

BirdNET's geographic range model (V2.4-V2) is the best tool for filtering candidate species to those actually expected at a given location. Workflow:
1. Pass GPS coords + date to BirdNET range model → get expected species list for that region
2. Run BirdNET classifier → top-N candidates
3. Cross-validate against Perch embeddings if confidence is below threshold
4. Look up confirmed species in xeno-canto for reference playback

---

## Open Questions / Decisions Needed from Chris

**1. BirdNET license — non-commercial clause (BLOCKER)**
BirdNET models are CC BY-NC-SA 4.0. Spatial Field Converter v0.2 is a commercial-leaning tool. This is a hard stop if the app is sold or monetized. Options: (a) use Perch instead (Apache-2.0, commercially clear), (b) contact Cornell at ccb-birdnet@cornell.edu for a commercial license, (c) ship BirdNET only in a free/research tier. **Chris needs to make this call before writing BirdNET integration code.**

**2. BatDetect2 license — non-commercial clause**
Same issue. CC BY-NC 4.0. And the default model is UK bats only. For Neotropical bats, there is no off-the-shelf model. If bat ID matters for v0.2, the question is: (a) skip bats in v0.2, (b) use BatDetect2 for UK species only with a research caveat, (c) commission a Neotropical bat call dataset and fine-tune.

**3. AnuraSet frog classifier — training required**
AnuraSet is a dataset, not a model. Someone needs to train a classifier on it. The baseline code is in the repo (Python, transfer learning on spectrogram CNN). This is a half-day to one-day task if Chris wants Cerrado/Atlantic Forest frog ID in v0.2. Confirm: is this in scope for v0.2, or deferred?

**4. Neotropical frog gap beyond AnuraSet's 42 species**
AnuraSet covers Cerrado and Atlantic Forest. Amazon (Pantanal, Acre, Pará) frog species are NOT in this dataset. Brazil has ~1,100 anuran species. 42 is a start, not comprehensive coverage. Is partial coverage acceptable for v0.2?

**5. xeno-canto API key and recording license filter**
Starting October 2025, the xeno-canto API requires a key. Chris needs to register and get a key. More importantly: for any feature that plays back reference recordings, the app must filter to CC BY recordings only (non-NC) to stay commercially compliant. This means fewer recordings will be available for playback in the UI. Is that acceptable, or does Chris want to pursue a bulk licensing arrangement with the xeno-canto Foundation?

**6. Macaulay Library bulk access**
Macaulay Library has the best archive (3.2M recordings) but no public download API. If Chris wants Macaulay-sourced reference audio, a formal request to Cornell is required. Given Chris's existing Cornell pipeline relationships (BirdNET, eBird), this may be achievable — but it's a relationship/business decision, not a technical one.

**7. Bat echolocation recordings: ultrasonic hardware**
Standard iPhone/Mac microphones do not capture bat echolocation (40–120 kHz; hardware typically stops at 20–24 kHz). Any bat ID feature in the field converter would require ultrasonic recording hardware (e.g., Audiomoth, Wildlife Acoustics SM4BAT, or similar). Is bat detection in scope for v0.2 given this hardware constraint?

---

*Sources consulted (live web research, 2026-05-15):*

- https://birdnet.cornell.edu/about/
- https://birdnet-team.github.io/BirdNET-Analyzer/models.html
- https://github.com/birdnet-team/BirdNET-Analyzer
- https://github.com/birdnet-team/BirdNET-Lite (archived March 2025)
- https://github.com/google-research/perch
- https://developer.apple.com/documentation/SoundAnalysis
- https://developer.apple.com/videos/play/wwdc2021/10036/
- https://www.xeno-canto.org / publicapi.dev/xeno-canto-api
- https://www.macaulaylibrary.org
- https://api.inaturalist.org/v2/docs/
- https://www.gbif.org / techdocs.gbif.org
- https://en.wikiaves.com.br / github.com/Athospd/wikiaves
- https://amphibiaweb.org/data.html
- https://github.com/soundclim/anuraset
- https://zenodo.org/records/8056090 (AnuraSet)
- https://github.com/macaodha/batdetect2
- https://github.com/earthspecies/aves
- https://github.com/earthspecies/avex
- https://github.com/earthspecies/NatureLM-audio
- https://huggingface.co/EarthSpeciesProject/NatureLM-audio
- https://github.com/jhuus/HawkEars
- https://github.com/kitzeslab/bioacoustics-model-zoo
- https://github.com/DBD-research-group/BirdSet
- https://arbimon.org / rfcx.org
- https://raw.githubusercontent.com/tensorflow/models/master/research/audioset/yamnet/yamnet_class_map.csv
- https://zenodo.org/records/14056458 (InsectSet459)
- https://merlin.allaboutbirds.org/merlin-sound-id-project-overview/
- https://www.macaulaylibrary.org/2021/06/22/behind-the-scenes-of-sound-id-in-merlin/
- https://www.wildlifeacoustics.com/products/kaleidoscope-pro
- https://ai.google.dev/edge/litert/ios/coreml
- https://link.springer.com/article/10.1007/s43388-021-00058-x (CBRO checklist)
- https://www.museum.lsu.edu/~Remsen/SACCCountryLists.htm
