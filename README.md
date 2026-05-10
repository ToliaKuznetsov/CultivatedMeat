# Framing the Future of Food
# Replication Code - RQ4 Computational Text Analysis

> **Kuznetsov, A. (2026).** *Framing the Future of Food: How Cultivated Meat Startups Strategically Use Language to Gain Legitimacy among Investors.* Master of Business Administration thesis, Walker School of Business, Webster Vienna Private University. Supervisor: Dr. Vitaliano Barberio.

# Overview

This repository contains the R replication code for Research Question 4 of the thesis: 
# How does linguistic framing in cultivated meat startup websites relate to fundraising outcomes?

The broader thesis employs a four-part mixed-methods design. The first three research questions rely on qualitative and discourse-analytic methods (thematic coding of 218 company websites, linguistic register analysis, and field-level framing classification across 213 companies). RQ4 shifts to a quantitative, reproducible approach: dictionary-based computational text analysis combined with OLS regression modelling on a verified sample of 60 firms.

---

#Thesis Structure

| RQ | Question | Method | N |
|----|----------|--------|---|
| RQ1 | How do cultivated meat startups construct their self-presentation on official websites? | Thematic coding, multimodal analysis | 218 companies |
| RQ2 | What linguistic registers build legitimacy, and how? | Discourse analysis (Fairclough, 2003) | Case-based |
| RQ3 | What field-level framing strategies exist, and how do they vary by geography and business model? | Deductive coding, κ = .74 | 213 companies |
| RQ4 | Does linguistic framing relate to fundraising outcomes? | Computational text analysis + OLS regression | 60 firms |

**This repository covers RQ4 only.**

---

## Repository Structure

```
CultivatedMeat/
├── cultivated.r            # Full RQ4 analysis pipeline (self-contained)
├── startup_table.xlsx      # Input data-one row per startup (not tracked)
└── outputs/                # Created automatically on first run
    ├── startup_clean.csv
    ├── startup_text_features.csv
    ├── descriptives.csv            # Table 1
    ├── correlation_matrix.csv      # Table 2
    ├── reg_moral.csv               # Model 1
    ├── reg_future.csv              # Model 2
    ├── reg_trust_positive.csv      # Model 3
    ├── reg_quadratic.csv           # Model 5
    ├── reg_full_controls.csv       # Model 6
    └── plot_future_vs_funding.png  # Figure 1
```


## Sample

The starting corpus comprised **67** cultivated meat and alternative protein startups drawn from AgFunder, GreenQueen, and the Good Food Institute's *State of the Industry* reports. Website texts (Mission, Values, About sections) were collected in February-March 2026.

- 2 firms excluded due to insufficient retrievable text -> **65 firms** in the text corpus
- All 65 met the minimum threshold of 80 words
- 5 firms had no publicly disclosed funding data -> **n = 60** in all regression models

The final sample spans companies from North America, Europe, Asia-Pacific, and Latin America, with founding years from 2011 to 2023. Of the 60 firms, 43 are B2B technology providers and 15 are B2C consumer-facing producers.

---

## Computational Text Measures

Three families of NLP features, all normalised **per 1,000 words**:

| Measure | Instrument | Source |
|---------|-----------|--------|
| Moral framing | Moral Foundations Dictionary 2.0 (MFD 2.0) | Hopp et al. (2021); `quanteda.dictionaries` |
| Emotional valence & discrete emotions (10 categories) | NRC Word-Emotion Association Lexicon | Mohammad & Turney (2013); `tidytext` |
| Temporal orientation (future / past / present) | Custom dictionary (purpose-built) | This study |

Non-English texts (primarily Mandarin and Portuguese) were machine-translated to English before scoring to ensure cross-sample consistency.

---

## Regression Models

The outcome variable is **log(1 + total_funding_musd)** - natural-log transformation of total disclosed funding (USD millions).

| Model | Predictors | n | Key result |
|-------|-----------|---|------------|
| M1 | `moral_total_per1k` | 60 | β = -0.005, n.s. |
| M2 | `future_per1k` | 60 | β = -0.002, n.s. |
| M3 | `trust + positive` | 60 | Both n.s.; R² = .039 |
| M4 | All text vars + `word_count`, `founded_year` | 60 | `founded_year` β = -0.381*** ; R² = .409 |
| M5 | `future_per1k + future_per1k²` (quadratic) | 60 | Suggestive inverted-U, n.s. overall |
| M6 | Full model + `region`, `b2b_dummy` | 53 | `moral` β =-0.024*, `b2b` β = -1.459**, North Am./Israel β = 1.423*; R² = .596 |

**Principal finding:** No linguistic variable significantly predicts funding across bivariate specifications. The single robust predictor is **founding year** (earlier-founded firms raise dramatically more, net of all linguistic characteristics). In the full model (M6), B2B orientation and North America/Israel origin emerge as the dominant structural predictors. The findings are interpreted as evidence of *communicative isomorphism*: shared legitimacy-oriented language has become a sector-wide table stake rather than a differentiating investment signal.

---

## Input Data

`startup_table.xlsx` must contain a sheet named **`startup_table`** with at minimum the following columns:

| Column | Description |
|--------|-------------|
| `company` | Startup name (unique identifier) |
| `mission` | Mission statement text |
| `value` | Value proposition text |
| `about` | "About us" text |
| `round_amount1` | First funding round (USD millions) |
| `round_amount2` | Second funding round (USD millions) |
| `total_funding` | Total funding disclosed (USD millions) |
| `founded_year` | Year of incorporation |
| `region` | Country / region of headquarters |
| `B2B_B2C` | Business model (`B2B` or `B2C`) |

Funding fields accept multiple formats: plain numbers (`5.2`), comma-decimal (`5,2`), K/M/B suffixes (`400K`), additive strings (`1.5+0.5`), and Excel arithmetic formulas (`=22.6+18`).

---

## Requirements

- **R** ≥ 4.2 (analyses conducted on R 4.4.0; R Core Team, 2024)
- CRAN packages - installed automatically on first run:

```r
dplyr, readr, stringr, tidyr, tidytext, purrr,
readxl, quanteda, textdata, ggplot2, broom
```

---

## How to Run

1. Clone the repository and place `startup_table.xlsx` in the project root.
2. Open `cultivated.r` and update the working directory path in Section 0:

```r
setwd("path/to/your/CultivatedMeat")
```

3. Source the script:

```r
source("cultivated.r")
```


## Citation

```
  author  = {Kuznetsov, Anatoly},
  title   = {Framing the Future of Food: How Cultivated Meat Startups
             Strategically Use Language to Gain Legitimacy among Investors},
  University  = {Webster Vienna Private University},
  year    = {2026},
  address = {Vienna, Austria},
  type    = {MBA} thesis}
```

