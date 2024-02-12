# CPRD Aurum Cohort scripts

## Introduction

This repository contains the R scripts used by the Exeter Diabetes team to produce three cohorts and their associated biomarker/comorbidity/sociodemographic data from a CPRD Aurum dataset: 
* An **'at-diagnosis'** cohort
* A **prevalent** cohort (registered at 01/02/2020)
* A **treatment response** (MASTERMIND) cohort (those initiating diabetes medications)

The below diagram outlines the data processing steps involved in creating these cohorts.

---
title: "Untitled"
format: gfm
---
```mermaid
graph TD;
    A["<b>CPRD Aurum October 2020 release</b> with linked Set 21 <br> (April 2021) HES APC, patient IMD, and ONS death data"] --> |"Unique patients with a diabetes-related medcode between 01/01/2004-06/11/2020 and >=1 year data prior and after"| B["<b>Our extract</b>: n=1,480,985*"]
    B -->|"With a diabetes QOF code with a valid date** (quality check to remove those without diabetes)"|C["n=1,138,193"]
    C --> |"Inconsistencies in diabetes type suggesting <br> coding errors or unclassifiable"|D["n=14"]
    C --> E["<b>Diabetes cohort</b>: n=1,138,179"]
    E --> F["<b>01 At-diagnosis cohort</b>: <br> n=771,678 <br> Index date=diagnosis date"]
    E --> G["<b>02 Prevalent cohort</b>: <br> n=643,143 <br> Actively registered on 01/02/2020 <br> Index date=diagnosis date"]
    E --> H["<b>03 Treatment response (MASTERMIND) cohort</b>: <br> n=995,036 with 3,218,100 unique drug periods <br> For T2D 1st instance dataset excluding drug starts within 91 days <br> of registration: n=769,394 with 1,663,398 unique drug periods <br> With script for diabetes medication <br> Index date=drug start date"]
```
\* Extract actually contained n=1,481,294 unique patients (1,481,884 in total but some duplicates) but included n=309 with registration start dates in 2020 (which did not fulfil the extract criteria of having a diabetes-related medcode between 01/01/2004-06/11/2020 and >=1 year of data after this; some of these were also not 'acceptable' by [CPRD's definition](https://cprd.com/sites/default/files/2023-02/CPRD%20Aurum%20Glossary%20Terms%20v2.pdf)). NB: removing those with registration start date in 2020 also removed all of those with a 'patienttypeid' not equal to 3 ('regular'). See next section for further details on the extract.
&nbsp;

\** A valid date is an obsdate (for medcodes) which is no earlier than the patient's date of birth (no earlier than the month of birth if date of birth is not available; no earlier than full date of birth if this is available), no later than the patient's date of death (earliest of cprd_ddeath (Patient table) and dod/dor where dod not available (ONS death data)) where this is present, no later than deregistration where this is present, and no later than the last collection date from the Practice. NB: QOF codes include codes for some non-Type 1/Type 2 diabetes types but not for gestational diabetes, so people with gestational diabetes codes only may be removed at this stage.

&nbsp;

## Extract details
Patients with a diabetes-related medcode ([full list here](https://github.com/Exeter-Diabetes/CPRD-Katie-MASTERMIND-Scripts/blob/main/Extract-details/diab_med_codes_2020.txt)) in the Observation table were extracted from the October 2020 CPRD Aurum release. See below for full inclusion criteria:

<img src="https://github.com/Exeter-Diabetes/CPRD-Cohort-scripts/blob/main/Extract-details/download_details1.PNG" width="370">

&nbsp;

<img src="https://github.com/Exeter-Diabetes/CPRD-Cohort-scripts/blob/main/Extract-details/download_details2.PNG" width="700">

&nbsp;

Note that as patients were required to have 1 year of data following their earliest (within study/UTS) diabetes code, there are few patients with diabetes diagnosed within the registration period who die within 1 year of diagnosis.

&nbsp;


## Script overview

The below diagram shows the R scripts (in grey boxes) used to create the final cohorts (at-diagnosis, prevalent, and treatment response).

```mermaid
graph TD;
    A["<b>Our extract</b> <br> with linked HES APC, patient IMD, and ONS death data"] --> |"all_diabetes_cohort <br> & all_patid_ethnicity"|B["<b>Diabetes cohort</b> with static <br> patient data including <br> ethnicity and IMD*"]
    A-->|"all_patid_ckd_stages"|C["<b>Longitudinal CKD stages</b> <br> for all patients"]
    A-->|"baseline_biomarkers <br> (requires index date)"|E["<b>Biomarkers</b> <br> at index date"]
    A-->|"comorbidities <br> (requires index date)"|F["<b>Comorbidities</b> <br> at index date"]
    A-->|"smoking <br> (requires index date)"|G["<b>Smoking status</b> <br> at index date"]
    A-->|"alcohol <br> (requires index date)"|H["<b>Alcohol status</b> <br> at index date"]
    C-->|"ckd_stages <br> (requires index date)"|I["<b>CKD stage</b <br> at index date"]
    B-->|"final_merge"|J["<b>Final cohort dataset</b>"]
    E-->|"final_merge"|J
    F-->|"final_merge"|J
    G-->|"final_merge"|J
    H-->|"final_merge"|J
    I-->|"final_merge"|J
```
\*IMD=Index of Multiple Deprivation; 'static' because we only have data from 2015.

&nbsp;

Each of the three final cohorts (at-diagnosis, prevalent, and treatment response) contains static patient data e.g. ethnicity, IMD and diabetes type from the diabetes cohort dataset, plus biomarker, comorbidity, and sociodemographic (smoking/alcohol) data at the (cohort-specific) index date.


This directory contains the scripts which are common to all three cohorts: 'all_diabetes_cohort', 'all_patid_ckd_stages', and 'all_patid_ethnicity'. These pull out static patient characteristics or features based on longitudinal data which may go beyond the index date of the cohorts (e.g. all_patid_ethnicity uses ethnicity codes from all time for each patient, which may occur later than the index date for a cohort).


In addition, this directory contains templates for the scripts which pull out data relative to the cohort index dates ('baseline_biomarkers', 'comorbidities', 'smoking', 'alcohol', 'ckd_stages' and 'final_merge'). The final cohorts each use tailored versions of these to account for the different index dates, the different biomarkers/comorbidities required for the different cohorts, and different additional inclusion/exclusion criteria which are applied in the 'final_merge' script. In addition to these differences, the cohorts have different additional scripts which pull in additional information e.g. the treatment response cohort has a 'drug_sorting_and_combos' script which defines the drug start dates which are used as the index dates, as well as scripts for biomarker responses (6/12 month post-index), which are used to evaluate treatment response.

The exact 'tailored' and additional scripts used to create each cohort dataset can be found in the relevant subdirectory: [01-At-diagnosis](https://github.com/Exeter-Diabetes/CPRD-Cohort-scripts/tree/main/01-At-diagnosis), [02-Prevalent](https://github.com/Exeter-Diabetes/CPRD-Cohort-scripts/tree/main/02-Prevalent), [03-Treatment-response-(MASTERMIND)](https://github.com/Exeter-Diabetes/CPRD-Cohort-scripts/tree/main/03-Treatment-response-(MASTERMIND)), along with a data dictionary of all variables in the final cohort dataset.

&nbsp;

## Script details

Data from CPRD was provided as raw text files which were imported into a MySQL database using a custom-built package ([aurum](https://github.com/Exeter-Diabetes/CPRD-analysis-package)) built by Dr Robert Challen. This package also includes functions to allow easy querying of the MySQL tables from R, using the 'dbplyr' tidyverse package. Codelists used for querying the data (denoted as 'codes${codelist_name}' in scripts) can be found in our [CPRD-Codelists repository](https://github.com/Exeter-Diabetes/CPRD-Codelists). 

Our [CPRD-Codelists repository](https://github.com/Exeter-Diabetes/CPRD-Codelists) also contains more details on the algorithms used to define variables such as ethnicity, diabetes diagnosis date, and diabetes type - see individual scripts for links to the appropriate part of the CPRD-Codelists repository.

| Script description | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Outputs&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; |
| ---- | ---- |
| **all_patid_ckd_stages**: uses eGFR calculated from serum creatinine to define longitudinal CKD stages for all patids as per [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#ckd-chronic-kidney-disease-stage) |  **all_patid_ckd_stages_from_algorithm**:  1 row per patid, with onset of different CKD stages in wide format |
| **all_patid_ethnicity**: uses GP and linked HES data to define ethnicity as per [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#ethnicity)  | **all_patid_ethnicity**:  1 row per patid, with 5-category, 16-category and QRISK2-category ethnicity (where available) |
| **all_diabetes_cohort**: table of patids meeting the criteria for our mixed Type 1/Type 2/'other' diabetes cohort plus additional patient variables | **all_diabetes_cohort**: 1 row per patid of those in the diabetes cohort, with diabetes diagnosis dates, DOB, gender, ethnicity etc. |
|**template_baseline_biomarkers**: pulls biomarkers value at cohort index dates | **{cohort_prefix}\_baseline_biomarkers**: 1 row per patid-index date combination with all biomarker values at index date where available (including HbA1c and height) |
|**template_comorbidities**: finds onset of comorbidities relative to cohort index dates | **{cohort_prefix}\_comorbidities**:  1 row per patid-index date combination, with earliest pre-index date code occurrence, latest pre-index date code occurrence, and earliest post-index date code occurrence |
|**template_smoking**: finds smoking status at cohort index dates | **{cohort_prefix}\_smoking**: 1 row per patid-index date combination, with smoking status and QRISK2 smoking category at index date where available |
|**template_alcohol**: finds alcohol status at cohort index dates | **{cohort_prefix}\_alcohol**: 1 row per patid-index date combination, with alcohol status at index date where available |
|**template_ckd_stages**: finds onset of CKD stages relative to cohort index dates | **{cohort_prefix}\_ckd_stages**: 1 row per patid-index date combination, with baseline CKD stage at index date where available |
|**template_final_merge**: pulls together variables from all of the above tables and adds age and diabetes duration at index date (not for at-diagnosis cohort as age at diagnosis variable already present from all_diabetes_cohort script) | **{cohort_prefix}\_final_merge**: 1 row per patid-index date combination with relevant biomarker/comorbidity/smoking/alcohol variables |

&nbsp;

## Data dictionary of variables in 'final_merge' table

Biomarkers included: HbA1c (mmol/mol), weight (kg), height (m), BMI (kg/m2), HDL (mmol/L), triglycerides (mmol/L), blood creatinine (umol/L), LDL (mmol/L), ALT (U/L), AST (U/L), total cholesterol (mmol/L), DBP (mmHg), SBP (mmHg), ACR (mg/mmol / g/mol).

Comorbidities included: atrial fibrillation, angina, asthma, bronchiectasis, CKD stage 5/ESRD, CLD, COPD, cystic fibrosis, dementia, diabetic nephropathy, haematological cancers, heart failure, hypertension, IHD, myocardial infarction, neuropathy, other neurological conditions, PAD, pulmonary fibrosis, pulmonary hypertension, retinopathy, (coronary artery) revascularisation, rhematoid arthritis, solid cancer, solid organ transplant, stroke, TIA.

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| patid | unique patient identifier | |
| index_date | index date (e.g. diagnosis date for 'at-diagnosis' cohort, 01/02/2020 for prevalent cohort, drug start date for treatment response cohort) | |
| index_date_age | age of patient at index date in years | index_date - dob |
| index_date_dm_dur_all | diabetes duration at index date in years for all patients (see below note on dm_diag_date_all) | index_date - dm_diag_date_all |
| gender | gender (1=male, 2=female) | |
| dob | date of birth | if month and date missing, 1st July used, if date but not month missing, 15th of month used, or earliest medcode in year of birth if this is earlier |
| pracid | practice ID | |
| prac_region | practice region: 1=North East, 2=North West, 3=Yorkshire And The Humber, 4=East Midlands, 5=West Midlands, 6=East of England, 7=South West, 8=South Central, 9=London, 10=South East Coast, 11 Northern Ireland, 12 Scotland, 13 Wales | |
| ethnicity_5cat | 5-category ethnicity: (0=White, 1=South Asian, 2=Black, 3=Other, 4=Mixed) | Uses [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#ethnicity) (NB: use all medcodes; no date restrictions):<br />Use most frequent category<br />If multiple categories with same frequency, use latest one<br />If multiple categories with same frequency and used as recently as each other, label as missing<br />Use HES if missing/no consensus from medcodes |
| ethnicity_16cat | 16-category ethnicity: (1=White British, 2=White Irish, 3=Other White, 4=White and Black Caribbean, 5=White and Black African, 6=White and Asian, 7=Other Mixed, 8=Indian, 9=Pakistani, 10=Bangladeshi, 11=Other Asian, 12=Caribbean, 13=African, 14=Other Black, 15=Chinese, 16=Other) | |
| ethnicity_qrisk2 | QRISK2 ethnicity category: (1=White, 2=Indian, 3=Pakistani, 4=Bangladeshi, 5=Other Asian, 6=Black Caribbean, 7=Black African, 8=Chinese, 9=Other) | |
| imd2015_10 | English Index of Multiple Deprivation (IMD) decile (1=least deprived, 10=most deprived) | |
| has_insulin | has a prescription for insulin ever (excluding invalid dates - before DOB / after LCD/death/deregistration) | |
| type1_code_count | number of Type 1-specific codes in records (any date) | |
| type2_code_count | number of Type 2-specific codes in records (any date) | |
| raw_dm_diag_dmcodedate | earliest diabetes medcode (including diabetes exclusion codes; excluding those with obstypeid=4 (family history) and invalid dates). 'Raw' indicates that this is before codes in the year of birth are removed for those with Type 2 diabetes | |
| raw_dm_diag_date_all | diabetes diagnosis date | earliest of raw_dm_diag_dmcodedate, dm_diag_hba1cdate, dm_diag_ohadate, and dm_diag_insdate. |
| dm_diag_dmcodedate | earliest diabetes medcode (including diabetes exclusion codes; excluding those with obstypeid=4 (family history) and invalid dates). Codes in year fof birth removed for those with Type 2 diabetes | |
| dm_diag_hba1cdate | earliest HbA1c >47.5 mmol/mol (excluding invalid dates, including those with valid value and unit codes only) | |
| dm_diag_ohadate | earliest OHA prescription (excluding invalid dates) | |
| dm_diag_insdate | earliest insulin prescription (excluding invalid dates) | |
| dm_diag_date_all | diabetes diagnosis date | earliest of dm_diag_dmcodedate, dm_diag_hba1cdate, dm_diag_ohadate, and dm_diag_insdate, but set to missing if this date is within -30 to +90 days (inclusive) of registration start<br />NB: as at-diagnosis cohort excludes those with diagnosis dates before registration start, this variable is missing and only dm_diag_age (below) is present<br />It's worth noting that we have a number of people classified as Type 2 who appear to have been diagnosed at a young age, which is likely to be a coding error. This small proportion shouldn't affect any analysis results greatly, but might need to be considered for other analysis |
| dm_diag_date | diabetes diagnosis date for those with diagnosis at/after registration start | as per dm_diag_date_all, but also missing if dm_diag_date_all is before registration start (so is missing if earliest of dm_diag_dmcodedate, dm_diag_hba1cdate, dm_diag_ohadate, and dm_diag_insdate is before or up to 90 days (inclusive) after registration start)<br />See above note next to dm_diag_date_all variable on young diagnosis in T2Ds |
| dm_diag_codetype | whether diagnosis date represents diabetes medcode (1), high HbA1c (2), OHA prescription (3) or insulin (4) - if multiple on same day, use lowest number | |
| dm_diag_age_all | age at diabetes diagnosis | dm_diag_date_all - dob<br />NB: as at-diagnosis cohort excludes those with diagnosis dates before registration start, this variable is missing and only dm_diag_age (below) is present<br />See above note next to dm_diag_date_all variable on young diagnosis in T2Ds |
| dm_diag_age | age at diabetes diagnosis for those with diagnosis at/after registration start | dm_diag_date - dob<br />See above note next to dm_diag_date_all variable on young diagnosis in T2Ds |
| dm_diag_before_reg | whether diagnosed before registration start | |
| ins_in_1_year | whether started insulin within 1 year of diagnosis (**0 may mean no or missing**) | |
| current_oha | whether prescription for insulin within last 6 months of data | last 6 months of data = those before LCD/death/deregistration |
| diabetes_type | diabetes type | See [algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#diabetes-algorithms)<br />See above note next to dm_diag_date_all variable on young diagnosis in T2Ds |
| regstartdate | registration start date | |
| gp_record_end | earliest of last collection date from practice, deregistration and 31/10/2020 (latest date in records) | |
| death_date | earliest of 'cprddeathdate' (derived by CPRD) and ONS death date | NA if no death date |
| with_hes | 1 for patients with HES linkage and n_patid_hes<=20, otherwise 0| |
| pre{biomarker} | biomarker value at baseline | For all biomarkers except HbA1c: pre{biomarker} is closest biomarker to index date within window of -730 days (2 years before index date) and +7 days (a week after index date)<br /><br />For HbA1c: prehba1c is closest HbA1c to index date within window of -183 days (6 months before index date) and +7 days (a week after index date) |
| pre{biomarker}date | date of baseline biomarker | |
| pre{biomarker}datediff | days between index date and baseline biomarker (negative: biomarker measured before index date) | |
| height | height in cm | Mean of all values on/post-index date |
| preckdstage | CKD stage at baseline | CKD stages calculated as per [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#ckd-chronic-kidney-disease-stage)<br />eGFR calculated from creatinine using CKD-EPI creatinine 2021 equation<br />Start date = earliest test for CKD stage, only including those confirmed by another test at least 91 days later, without a test for a different stage in the intervening period<br />Baseline stage = maximum stage with start date < index date or up to 7 days afterwards<br />CKD5 supplemented by medcodes/ICD10/OPCS4 codes for CKD5 / ESRD |
| preckdstagedate | date of onset of baseline CKD stage (earliest test for this stage) | |
| preckdstagedatediff | days between index date and preckdstagedate | |
| pre_index_date_earliest_{comorbidity} | earliest occurrence of comorbidity before/at index date | |
| pre_index_date_latest_{comorbidity} | latest occurrence of comorbidity before/at index date | |
| pre_index_date_{comorbidity} | binary 0/1 if any instance of comorbidity before/at index date | |
| post_index_date_first_{comorbidity} | earliest occurrence of comorbidity after (not at) index date | |
| smoking_cat | Smoking category at index date: Non-smoker, Ex-smoker or Active smoker | Derived from [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#smoking) |
| qrisk2_smoking_cat | QRISK2 smoking category code (0-4) | |
| qrisk2_smoking_cat_uncoded | Decoded version of qrisk2_smoking_cat: 0=Non-smoker, 1= Ex-smoker, 2=Light smoker, 3=Moderate smoker, 4=Heavy smoker | |
| alcohol_cat | Alcohol consumption category at index date: None, Within limits, Excess or Heavy | Derived from [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#alcohol) |
