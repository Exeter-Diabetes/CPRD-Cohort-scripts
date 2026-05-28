# Copilot Instructions

## Project Overview

This repository contains R scripts used by the **Exeter Diabetes team** to create diabetes research cohorts from a **CPRD Aurum** dataset (Clinical Practice Research Datalink). Data from CPRD is stored in a MySQL database and queried from R via the [`aurum`](https://github.com/Exeter-Diabetes/CPRD-analysis-package) package, which wraps `dbplyr`/`tidyverse` to allow lazy evaluation against the remote MySQL tables.

Three cohorts are produced:
- **At-diagnosis** (`01-At-diagnosis/`): index date = diabetes diagnosis date
- **Prevalent** (`02-Prevalent/`): index date = a specific registration date
- **Treatment response / MASTERMIND** (`03-Treatment-response-(MASTERMIND)/`): index date = drug start date

Scripts that are shared across all cohorts live in the root directory. Cohort-specific scripts live in their subdirectory and are prefixed with their cohort short name (e.g. `at_diag_`, `prev_`, `mm_`).

---

## Architecture & Data Flow

1. **Root scripts** (`all_diabetes_cohort.R`, `all_patid_ethnicity.R`, `all_patid_ckd_stages.R`, `all_patid_death_causes.R`) produce patient-level MySQL tables that are shared across cohorts.
2. **Template scripts** (`template_baseline_biomarkers.R`, `template_comorbidities.R`, `template_smoking.R`, `template_alcohol.R`, `template_ckd_stages.R`, `template_final_merge.R`) are the canonical patterns for building index-date-relative features. Each cohort has a tailored copy.
3. **Final merge scripts** (`*_final_merge.R`) join all feature tables into one wide table per cohort. They always produce **1 row per patid** (at-diagnosis, prevalent) or **1 row per patid–index date** (MASTERMIND).

Output tables follow the naming convention: `{cohort_prefix}_{script_type}` (e.g. `at_diag_baseline_biomarkers`, `mm_comorbidities`).

---

## Infrastructure

All R scripts run on **Slade** (University of Exeter Linux server) via an SSH connection, accessing a **MySQL database** through the `aurum` R package. Scripts are written locally and run on Slade using RStudio via X11 forwarding (MobaXterm on Windows). The connection is configured via `~/.aurum.yaml`. 

Individual patient-level data must never leave Slade (no local saves, no GitHub uploads). Only aggregate statistics (counts, means, etc.) can be exported.

---

## Setup Pattern

Every script begins with the same boilerplate:

```r
library(tidyverse)
library(aurum)
library(EHRBiomarkr)   # only where biomarker cleaning functions are needed
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024", cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "01/06/2024")

analysis = cprd$analysis("at_diag")   # or "mm", "prev", "all_patid", etc.
```

- `cprdEnv` refers to the MySQL environment defined in `~/.aurum.yaml`.
- `codes` is a named list of codelists; use `codes$<codelist_name>` to access them.
- `cprd$tables$<tablename>` gives a lazy `dbplyr` handle to a raw CPRD MySQL table (e.g. `cprd$tables$observation`, `cprd$tables$patient`, `cprd$tables$drugIssue`, `cprd$tables$hesDiagnosisEpi`).

---

## How `cprd$analysis` and `analysis$cached` Work

This is the central pattern for managing MySQL tables in the codebase. Understanding it is essential.

### `cprd$analysis(name)` — setting the table namespace

```r
analysis = cprd$analysis("at_diag")
```

This sets the **MySQL table name prefix** for any tables subsequently cached with `analysis$cached()`. A table cached as `"baseline_biomarkers"` under this analysis is physically stored in MySQL as **`at_diag_baseline_biomarkers`**.

You switch the analysis context frequently within the same script to write tables to the correct namespace:

```r
analysis = cprd$analysis("all_patid")     # subsequent caches → all_patid_*
raw_smoking_medcodes <- cprd$tables$observation %>%
  inner_join(codes$smoking, by="medcodeid") %>%
  analysis$cached("raw_smoking_medcodes", indexes=c("patid", "obsdate"))
  # → stored as: all_patid_raw_smoking_medcodes

analysis = cprd$analysis("at_diag")      # switch namespace
smoking <- ... %>%
  analysis$cached("smoking", indexes=c("patid", "index_date"))
  # → stored as: at_diag_smoking
```

### `analysis$cached(name, indexes, unique_indexes)` — saving and reusing tables

```r
my_table <- my_query %>% analysis$cached("my_table",
                                          indexes = c("patid", "date"),
                                          unique_indexes = "patid")
```

- Executes the `dbplyr` query and materialises the result as a MySQL table.
- Returns a lazy handle pointing to the newly created MySQL table.
- **Does NOT overwrite** if the table already exists — it returns a pointer to the existing table and skips the query entirely. To force a re-run, you must delete the table in MySQL first (e.g. via MySQL Workbench or `DBI::dbRemoveTable`).
- **Re-running a script is safe**: because caching never overwrites, running the same script a second time will simply reconnect to all the already-cached tables and skip all computation. This also means that if you give two different queries the same cache name, the second one will silently return the first — always use distinct names.
- **Interim caching for long queries**: complex pipelines are deliberately split into multiple `analysis$cached()` steps with intermediate names (e.g. `"ohains_interim_1"`, `"ohains_interim_2"`). This way, if a later step fails or needs changing, only that step needs to be deleted and re-run — earlier steps remain cached and are reused instantly.
- `indexes` speeds up future joins/filters on those columns. `unique_indexes` additionally enforces uniqueness.
- Always cache intermediate results that will be reused, especially within loops over biomarkers or comorbidities.

### Getting a handle to an already-cached table

When you need to use a table that was cached by a previous script, use the same pattern but assign from an uninitialised variable — the package resolves it to the MySQL table:

```r
analysis = cprd$analysis("all")
diabetes_cohort <- diabetes_cohort %>% analysis$cached("diabetes_cohort")
```

This does **not** re-run any computation. It creates a lazy pointer to `all_diabetes_cohort` in MySQL.

### All operations are lazy until `cached()` or `collect()`

Every `dplyr` verb applied to a `cprd$tables$...` or cached handle builds up SQL without executing it. Nothing runs against MySQL until:
- `analysis$cached(...)` is called (materialises to MySQL), or
- `collect()` is called (pulls data into R memory — avoid for large tables; only use for final aggregate stats).

You can use `show_query()` at any point to inspect the SQL being generated:

```r
cprd$tables$observation %>% inner_join(codes$creatinine_blood, by="medcodeid") %>% show_query()
```

---

## Dropping MySQL Tables

When a script needs to be re-run (e.g. because the logic has changed), the affected cached tables must first be deleted from MySQL. Always ask the user for the **MySQL database name** before generating any DROP statements — it is not the same as the `cprdEnv` string and varies per project.

### Table naming
Every cached table is stored in MySQL as:
```
{analysis_prefix}_{table_name}
```
where `analysis_prefix` is the string passed to `cprd$analysis(...)` at the time of caching (e.g. `all_patid`, `at_diag`, `mm`, `PC_BP`).

### DROP TABLE format
Use a single `DROP TABLE IF EXISTS` statement listing all tables as `` `database`.`table` `` pairs, separated by commas and ending with a semicolon:

```sql
DROP TABLE IF EXISTS
  `<database>`.`<analysis_prefix>_<table_name>`,
  `<database>`.`<analysis_prefix>_<table_name>`;
```

- Always use backtick-quoting for both database and table names.
- Use `IF EXISTS` to avoid errors if a table hasn't been created yet.
- List all tables to drop in a single statement for efficiency.

---

## Coding Conventions

### General R style
- Use `tidyverse`/`dplyr` verbs (`filter`, `mutate`, `select`, `group_by`, `summarise`, `left_join`, `inner_join`, `anti_join`, `union_all`).
- Always `rm(list=ls())` at the start of a script.
- Use `<-` for assignment (not `=`).
- Separate logical sections with comment banners:
  ```r
  ############################################################################################
  ```
- Comment counts after caching tables (e.g. `# 2,081,032`) to serve as sanity checks.
- Use `%>%` pipes, not `|>`.

### dbplyr / MySQL quirks
Because all queries are translated from R to MySQL via `dbplyr`, several standard R/dplyr functions do not work and have MySQL equivalents:

| Don't use | Use instead |
|-----------|-------------|
| `difftime()` | `datediff(date1, date2)` — returns days as integer |
| `rbind()` | `union_all()` |
| `arrange()` | `window_order()` |
| `median()` | not supported; use `percentile_cont` via raw SQL if needed |
| `slice()` | not supported; use `filter(row_number() == 1)` with `window_order` |
| `first()` in `summarise()` | not supported in a remote `summarise()` context; if the column is constant within the group use `min()` or `max()`; if you need the first of a varying column, pre-sort with `window_order()` then `filter(row_number() == 1)` in a `mutate()` step before summarising |

When pulling data into R with `collect()`, `patid` and similar large integer fields may arrive as `integer64`, which causes errors in many R functions. Convert with:
```r
# For most fields:
table <- table %>% mutate_if(is.integer64, as.integer)
# For patid specifically (too large for integer):
table <- table %>% mutate(patid = as.character(patid))
```

### Caching & analysis contexts
- Switch `analysis = cprd$analysis("...")` before caching to control which MySQL prefix is used.
- Use `analysis$cached()` for all intermediate and final tables. Never rely on local R objects as the sole copy of a result.
- Raw tables cached under `"all_patid"` analysis are shared; cohort-specific tables go under the cohort analysis (e.g. `"at_diag"`, `"mm"`).

### Naming conventions
- Raw pulled tables: `raw_{feature}_medcodes`, `raw_{feature}_icd10`
- Cleaned tables: `clean_{feature}_medcodes`
- Pre/post-index merged tables: `pre_index_date_{feature}_merge`
- Final output columns: `pre_index_date_earliest_{comorbidity}`, `pre_index_date_latest_{comorbidity}`, `pre_index_date_{comorbidity}` (binary 0/1), `post_index_date_first_{comorbidity}`

### Date filtering
- Always validate dates against `validDateLookup` (contains `min_dob`, `gp_end_date`, `gp_ons_end_date`).
- Standard filter: `obsdate >= min_dob & obsdate <= gp_ons_end_date`.
- Index-date windows vary by feature:
  - Most biomarkers: −2 years to +7 days
  - HbA1c: −6 months to +7 days
  - Height: mean of all values ≥ index date
  - Smoking/comorbidity codes: all pre-index + up to 7 days post-index (`datediff(date, index_date) <= 7`)

### Joining codelists
- SNOMED/Read (GP) codes: `inner_join(codes$<codelist>, by="medcodeid")`
- ICD-10 (HES): `inner_join(codes$icd10_<codelist>, sql_on="LHS.ICD LIKE CONCAT(icd10,'%')")`
- Do NOT include ICD-10 codes for hypertension (GP codes only for that condition).

### Biomarkers (`EHRBiomarkr` package)
- Clean using `clean_biomarker_values(testvalue, "<biomarker>")` and `clean_biomarker_units(numunitid, "<biomarker>")`.
- After cleaning, average duplicate readings on the same day: `group_by(patid, obsdate) %>% summarise(testvalue = mean(testvalue, na.rm=TRUE))`.
- HbA1c-specific: convert % to mmol/mol with `ifelse(testvalue<=20, ((testvalue-2.152)/0.09148), testvalue)` before cleaning.

### Comorbidities
- The standard comorbidity list and loop pattern from `template_comorbidities.R` should be followed when adding new comorbidities.
- To add a new comorbidity, append it to the `comorbids` vector and ensure corresponding codelists exist in the codelist repository. Delete the cached final `comorbidities` table to force re-run.
- Same pattern applies to biomarkers in the `biomarkers` vector.

### Diabetes medications

#### Source tables
- `all_patid_clean_oha_prodcodes` — oral hypoglycaemic agent (OHA) prescriptions, cleaned and classified, produced by `all_diabetes_cohort.R`. Has columns: `patid`, `date`, and **numbered pairs** `drug_class_N` / `drug_substance_N` (N = 1, 2, …). Single-drug prescriptions only have `_1` columns; combination products have additional `_2`, `_3`, … columns for each component.
- `all_patid_clean_insulin_prodcodes` — insulin prescriptions with `insulin_cat` column identifying the type.
- These are combined into `mm_ohaandins` and then pivoted long into `mm_ohains` — **one row per drug class/substance per prescription date**. `mm_ohains` is the safe starting point for almost all medication analyses.

#### Combination products
Combination pills (e.g. metformin + sitagliptin) are stored as a single row in `clean_oha_prodcodes` with multiple numbered column pairs. The pattern is resolved by a `pivot_longer` that matches any `_N` suffix:

```r
pivot_longer(
  cols         = c(starts_with("drug_class"), starts_with("drug_substance")),
  names_to     = c(".value", "row"),
  names_pattern = "([A-Za-z]+_[A-Za-z]+)_(\\d+)"
)
```

This collapses all `drug_class_N` columns into a single `drug_class` column and all `drug_substance_N` columns into `drug_substance`, giving **1 row per component per prescription**. The MASTERMIND `ohains` table is the result of this pivot (with insulin added and same-day duplicates removed).

#### Drug class vs drug substance
Every prescription has both a `drug_class` (broad pharmacological group) and a `drug_substance` (specific molecule). Use `drug_class` for most analyses; use `drug_substance` when distinguishing within-class differences (e.g. semaglutide dose, exenatide formulation).

**Drug classes** (10 total, as used in `01_mm_drug_sorting_and_combos.R`):

| Code | Class |
|------|-------|
| `MFN` | Metformin |
| `SU` | Sulphonylurea |
| `DPP4` | DPP-4 inhibitor |
| `SGLT2` | SGLT-2 inhibitor |
| `GLP1` | GLP-1 receptor agonist |
| `GIPGLP1` | GIP/GLP-1 dual agonist (tirzepatide) |
| `TZD` | Thiazolidinedione |
| `INS` | Insulin |
| `Glinide` | Glinide |
| `Acarbose` | Acarbose |

**Drug substances** (37 total):

| Class | Substances |
|-------|-----------|
| MFN | Metformin |
| SU | Gliclazide, Glimepiride, Glipizide, Glibenclamide, Gliquidone, Glymidine, Chlorpropamide, Tolazamide, Tolbutamide |
| DPP4 | Sitagliptin, Saxagliptin, Alogliptin, Linagliptin, Vildagliptin |
| SGLT2 | Dapagliflozin, Empagliflozin, Canagliflozin, Ertugliflozin |
| GLP1 | Liraglutide, Dulaglutide, Exenatide, Exenatide prolonged-release, Lixisenatide, Albiglutide, Low-dose semaglutide, High-dose semaglutide, Oral semaglutide, Semaglutide (dose unclear) |
| GIPGLP1 | Tirzepatide |
| TZD | Pioglitazone, Rosiglitazone, Troglitazone |
| INS | Insulin (all types collapsed to single substance in MASTERMIND) |
| Glinide | Repaglinide, Nateglinide |
| Acarbose | Acarbose |

#### Start/stop episode logic (MASTERMIND)
- A new **drug episode** starts if there is no prior prescription for that drug class/substance, or if the gap since the last prescription exceeds **183 days** (6 months).
- `dstart_class` / `dstop_class`: boolean flags for episode start/stop at the drug-class level.
- `dstart_substance` / `dstop_substance`: same at the drug-substance level.
- `drug_class_combo` / `drug_substance_combo`: underscore-concatenated string of all active classes/substances at each date (e.g. `"MFN_SGLT2"`).
- `numdrugs_class` / `numdrugs_substance`: count of active drug classes/substances at each prescription date.

#### Prescribing lookups for non-MASTERMIND analyses

**Preferred approach** — reuse `mm_ohains` (or apply the same pivot to `clean_oha_prodcodes` yourself) so you work with clean single `drug_class` / `drug_substance` columns:

```r
# Get a handle to ohains
analysis = cprd$analysis("mm")
ohains <- ohains %>% analysis$cached("ohains")

# Filter to the class or substance you need
glp1_scripts  <- ohains %>% filter(drug_class == "GLP1")
tzp_scripts   <- ohains %>% filter(drug_class == "GIPGLP1")
sglt2_scripts <- ohains %>% filter(drug_class == "SGLT2")
```

**Shortcut (single-component drugs only)** — filtering `clean_oha_prodcodes` on `drug_class_1` is safe when the drug class is *never* a component of a combination product (e.g. GLP-1 agonists, tirzepatide, insulin). Do **not** use this shortcut for MFN, SU, DPP4, or SGLT2, which commonly appear as `drug_class_2` in combination pills — you would silently miss those prescriptions.

**Avoid** joining `cprd$tables$drugIssue` against separate prodcode codelists for diabetes drugs: the classification work is already done in `clean_oha_prodcodes` / `ohains`.

### Final merge
- Always use `left_join` (not `inner_join`) when merging feature tables onto the cohort, to preserve all patients.
- Add derived fields (e.g. age at index, diabetes duration) using `datediff(index_date, dob)/365.25`.
- Use `relocate()` to place key variables near the front.

---

## Project-specific Requirements

### Cohort exclusions (standard, applied in `all_diabetes_cohort.R`)
- Remove patients from 44 specific practices that may have merged (CPRD recommendation).
- Remove patients with `gender==3` (indeterminate).
- Remove patients with diabetes insipidus codes.
- Remove patients with gestational diabetes codes.

### CPRD Aurum release
- Current extract: **June 2024** (`cprdEnv = "diabetes-jun2024"`).
- Linked data: HES APC (November 2024), patient IMD (2019), ONS death.
- Codelist version used in production scripts: `"01/06/2024"`. Template scripts use `"31/10/2021"` as a placeholder — update when adapting templates for production.

### Codelists
- All codelists live in the [CPRD-Codelists repository](https://github.com/Exeter-Diabetes/CPRD-Codelists).
- Reference algorithms for: ethnicity, diabetes diagnosis date, diabetes type, CKD staging, smoking, HbA1c.

### Analysis prefixes
| Prefix | Used for |
|--------|----------|
| `all_patid` | Tables shared across all cohorts (raw/clean medcodes, ethnicity, etc.) |
| `diabetes_cohort` | The core diabetes cohort definition |
| `all` | Cross-cohort outputs (diabetes_cohort, death_causes) |
| `at_diag` | At-diagnosis cohort |
| `prev` | Prevalent cohort |
| `mm` | Treatment response (MASTERMIND) cohort |
