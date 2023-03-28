# Data Dictionary

Intermediate tables and variables used for working not included. Self-explanatory variables like patid and drugclass not included.

## Script: 01_mm_drug_sorting_and_combos
### Table: mm_ohains / mm_all_scripts_long (ohains lacks dstart/dstop/num* variables)

1 line per patid / date / drug class (for which there is a prescription) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| quantity | number of tablets/items in prescriptions | provided by CPRD in drug issue table, directly from GP records<br />if 0, assume missing<br />if multiple prescriptions for same patid/date/drug, take mean |
| daily_dose | number of tablets/items prescribed per day | provided by CPRD (in dosage lookup ('common doses') - need to merge with dosageid in Drug Issue table), 'derived using CPRD algorithm based on free text'<br />if 0, assume missing<br />if multiple prescriptions for same patid/date/drug, take mean |
| duration | number of days prescription is for | provided by CPRD in drug issue table, no info on source so presumably from GP records<br />if 0, assume missing<br />if multiple prescriptions for same patid/date/drug, take mean |
| coverage | days of meds for that script | quantity/daily_dose if neither are missing, or use duration<br />NB: very high missingness in Aurum (~60%) |
| drugsubstances | drug substances within that class prescribed on that date | from [drug substance class lookup](https://github.com/Exeter-Diabetes/CPRD-Katie-MASTERMIND-Scripts/blob/main/Scripts/drug_substance_class_lookup.txt)<br />if multiple prescriptions for same patid/date/drug with different drug substances, combined using ' & ' as a separator |
| dstart | whether date is start date for that drug class (binary 0 or 1) | dstart=1 if it is the earliest script of that drug class for that person, or if previous script was >183 days (6 months) prior |
| dstop | whether date is stop for that drug class (binary 0 or 1) | dstop=1 if it is the last script of that drug class for that person, or if next script is >183 days (6 months) after |
| numpxdate | number of different drug classes prescribed that day (duplicated within patid/date) | |
| numstart | number of drug classes started on that day (duplicated within patid/date) | sum of dstart on that day |
| numstop | number of drug classes stopped on that day (duplicated within patid/date) | sum of dstop on that day |

&nbsp;

### Table: mm_all_scripts

1 line per patid / date (drugclass specific variables in wide format) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| cu_numstart | cumulative sum of numstart up to this date | |
| cu_numstop | cumulative sum of numstop up to this date | |
| numdrugs | number of drug classes patient is on at that date including ones stopped on that date | calculated as: cu_numstart - cu_numstop + numstop (add numstop so includes drug stopped on that day<br />NB: numdrugs2 is identical - calculated as sum of binary drug class columns (see next row) to check |
| Acarbose / DPP4 / Glinide / GLP1 / MFN / SGLT2 / SU / TZD / INS | binary variable of whether patient taking that drugclass on that date (regardless of whether or not prescribed on that date) | calculated using dstart and dstop vars for that particular drug class: 1 if cumsum(dstart)>cumsum(dstop) | dstart==1 | dstop==1 |
| INS_startdate | start date for insulin which is being taken on this date | uses dstart=1 - see above |
| INS_stopdate | stop date for insulin which is being taken on this date | uses dstop=1 - see above |
| drugcombo | combination of drug classes patient is on at that date | made by concatenating names of drug classes which patient is on at that date (from binary variables; separated by '\_') |
| dcstart | whether date is start date for drug combo | uses drugcombo variable: 1 if it is the earliest instance of that drug combo for that person, or if previous script was >183 days (6 months) prior |
| dcstop | whether date is stop for drug combo | uses drugcombo variable: 1 if it is the last instance of that drug combo for that person, or if next script is >183 days (6 months) after |
| timetolastpx | time from date to last prescription date for patient (in days) | |

&nbsp;

### Table: mm_drug_start_stop

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| dstartdate | drug class start date | uses dstart=1 - see above |
| dstopdate | drug class stop date | uses dstop=1 - see above |
| dstopdatepluscov | drug class stop date + coverage from last prescription | |
| drugsubstances | see above - based on what they got for their first prescription only; some people have >1 type if they got prescriptions for more than one type on that day | NB: each drug period has drug substance defined by whatever they were prescribed on the first day of starting that drug class. Validation analysis has shown that the percentage of scripts within each drug period with the same drug substance as the first script is >80% for all drug substances except the older SUs (glibenclamide, tolbutamid, chlorpropamid, gliquidone, tolazamide), rosiglitazone, and the older GLP1s (exenatide, lixisenatide, albiglutide), as people tend to be switched to newer agents (gliclazide for the SUs, pioglitazone for rosigliltazone, liraglutide for the GLP1s) during the drug period |
| timeondrug | dstopdate-dstartdate (in days) | |
| timeondrugpluscov | dstoppluscovdate-dstartdate (in days) | |
| drugorder | order within patient | e.g. patient takes MFN, SU, MFN, TZD in that order = 1, 2, 3, 4 |
| drugline_all / drugline | drug line<br />drugline_all is not missing for any drug periods<br />In final merge script, 'drugline' is the same as 'drugline_all' except it is set to missing if diabetes diagnosis date < registration (this is the only reason why this variable would be missing) | just takes into account first instance of drug e.g. patient takes MFN, SU, MFN, TZD in that order = 1, 2, 1, 4<br />if multiple drug classes started on same day, use minimum drug line for both |
| druginstance | 1st, 2nd, 3rd etc. period of taking this specific drug class | |

&nbsp;

### Table: mm_combo_start_stop

1 line per patid / drug combo instance (continuous period of drug combo use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| dcstartdate | drug combo start date | uses dcstart - see above |
| dcstopdate | drug combo stop date | uses dcstop - see above |
| drugcomboorder | order within patient | e.g. patient takes MFN only, MFN+SU, MFN+SU+DPP4 in that order = 1, 2, 3 |
| nextdcdate | date of next drug combination | doesn't include breaks i.e. when patient on none of the drug classes |
| add | number of drug classes added compared to previous drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />0 if none added / no previous drug combo as this is the first |
| rem | number of drug classes removed compared to previous drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />0 if none removed / no previous drug combo as this is the first |
| swap | 1 if at least one drug class added and at least one drug class removed compared to previous drug combo (doesn't take into account breaks when patient is on no diabetes meds) | uses add and rem<br />0 if no swap (i.e. drugs only added or removed) / no previous drug combo as this is the first |
| adddrug | names of drug classes added from previous drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />NA if none added / no previous drug combo as this is the first |
| remdrug | names of drug classes removed from previous drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />NA if none removed / no previous drug combo as this is the first |
| nextadd | number of drug classes added to get next drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />0 if none added / no next drug combo as this is the last before end of prescriptions |
| nextrem | number of drug classes added to get next drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />0 if none removed / no next drug combo as this is the last before end of prescriptions |
| nextswap | 1 if at least one drug class added and at least one drug class removed to get next drug combo (doesn't take into account breaks when patient is on no diabetes meds) | uses nextadd and nextrem<br />0 if no swap (i.e. drugs only added or removed) / no next drug combo as this is the last before end of prescriptions |
| nextaddrug | names of drug classes added to get next drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />NA if none added / no next drug combo as this is the last before end of prescriptions |
| nextremdrug | names of drug classes removed to get next drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />NA if none removed / no next drug combo as this is the last before end of prescriptions |
| drugchange | what change from previous drug combo to present one represents: add / remove / swap / (no previous combo as this is the) start of px / restart of same combo after break: stop - break<br />(doesn't take into account breaks when patient is on no diabetes meds) | if add>=1 & rem==0 -> add<br />if add==0 & rem>=1 -> remove<br />if add>=1 & rem>=1 -> swap<br />if add==0 & rem==0 & drugcomboorder==1 -> start of px<br />if add==0 & rem==0 & drugcomboorder!=1 -> stop - break |
| nextdrugchange | what change from present drug combo to next one represents: add / remove / swap / (no next combo as this is the) end of px / restart of same combo after break: stop - break<br />(doesn't take into account breaks when patient is on no diabetes meds) | if nextadd>=1 & nextrem==0 -> add<br />if nextadd==0 & nextrem>=1 -> remove<br />if nextadd>=1 & nextrem>=1 -> swap<br />if nextadd==0 & nextrem==0 & nextdcdate!=dcstopdate -> stop - break<br />if nextadd==0 & nextrem==0 & nextdcdate==dcstopdate -> stop - end of px |
| timetochange | time until changed to different drug combo in days (**does** take into account breaks when patient is on no diabetes meds) | if last combination before end of prescriptions, or if next event is a break from all drug classes, use dcstopdate to calculate |
| timetoaddrem | time until another drug class added or removed in days | NA if last combination before end of prescriptions |
| timeprevcombo | time since started previous drug combo in days | NA if no previous combo - i.e. at start of prescriptions<br />does not take into account breaks (i.e. if patient stops all drug classes) |
| multi_drug_start | whether multiple drug classes started on this dcstartdate | If add>1, multi_drug_start= 1 (yes), otherwise multi_drug_start=0 (no) |

&nbsp;

## Script: 02_mm_baseline_biomarkers
### Table: mm_baseline_biomarkers

Biomarkers included currently: weight, height, bmi, fastingglucose, hdl, triglyceride, blood creatinine, ldl, alt, ast, totalcholesterol, dbp, sbp, acr, hba1c, egfr (from blood creatinine), blood albumin, bilirubin, haematocrit, haemoglobin, PCR, urine albumin, urine creatinine (latter two not included but separately but combined where on the same day to give 'acr_from_separate' values.

NB: BMI and ACR are from BMI and ACR specific codes only, not calculated from weight+height / albumin+creatinine measurements

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| pre{biomarker} | biomarker value at baseline | For all biomarkers except HbA1c: pre{biomarker} is closest biomarker to dstartdate within window of -730 days (2 years before dstartdate) and +7 days (a week after dstartdate)<br /><br />For HbA1c: prehba1c is closest HbA1c to dstartdate within window of -183 days (6 months before dstartdate) and +7 days (a week after dstartdate) |
| pre{biomarker}date | date of baseline biomarker | |
| pre{biomarker}drugdiff | days between dstartdate and baseline biomarker (negative: biomarker measured before drug start date) | |
| height | height in cm | Mean of all values on/post- drug start date |

&nbsp;

## Script: 03_mm_biomarker_response
### Table: mm_biomarker_response

Biomarkers included currently: weight, bmi, fastingglucose, hdl, triglyceride, blood creatinine, ldl, alt, ast, totalcholesterol, dbp, sbp, acr, hba1c, egfr (from blood creatinine), blood albumin, bilirubin, haematocrit, haemoglobin, PCR, acr_from_separate as above (02_mm_baseline_biomarkers).

NB: BMI and ACR are from BMI and ACR specific codes only, not calculated from weight+height / albumin+creatinine measurements

1 line per patid / drug class instance (continuous period of drug class use) for all patids. Only uses first instance of use of that drug class.

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| post{biomarker}6m | biomarker value at 6m post drug initiation | post{biomarker}6m: closest biomarker to dstartdate+183 days (6 months), at least 3 months (91 days) after dstartdate, before 9 months, before timetoremadd (another drug class add or removed), and before timetochange+91 days (for most drug periods, timetoremadd=timetochange, they are only different if before a break, in which case timetochange<timetoremadd as timetochange doesn't include period of break and timetoremadd does - so biomarker can be within break period, up to 91 days after stopping drug of interest).<br /><br />No posthba1c6m value where changed diabetes meds <= 61 days before drug start (timeprevcombo<=61) |
| post{biomarker}6mdate | date of biomarker at 6m post drug initiation | |
| post{biomarker}6mdrugdiff | days between dstartdate and post{biomarker}6mdate | |
| post{biomarker}12m | biomarker value at 12m post drug initiation | posthba1c12m: closest biomarker to dstartdate+365 days (12 months), at least 9 months (274 days) after dstartdate, before 15 months, before timetoremadd (another drug class add or removed), and before timetochange+91 days (for most drug periods, timetoremadd=timetochange, they are only different if before a break, in which case timetochange<timetoremadd as timetochange doesn't include period of break and timetoremadd does - so biomarker can be within break period, up to 91 days after stopping drug of interest).<br /><br />No posthba1c12m value where changed diabetes meds <= 61 days before drug start (timeprevcombo<=61) |
| post{biomarker}12mdate | date of biomarker at 12m post drug initiation | |
| post{biomarker}12mdrugdiff | days between dstartdate and post{biomarker}6mdate | |
| {biomarker}resp6m | post{biomarker}6m - pre{biomarker} | |
| {biomarker}resp12m | post{biomarker}12m - pre{biomarker} | |
| next_egfr_date | date of first eGFR post-baseline | |
| egfr_40_decline_date | date at which eGFR<=40% of baseline value | |

&nbsp;

## Script: 04_mm_comorbidities
### Table: mm_comorbidities

Comorbidities included currently: af, angina, asthma, bronchiectasis, ckd5_code, cld, copd, cysticfibrosis, dementia, diabeticnephropathy, fh_premature_cvd, haem_cancer, heartfailure, hypertension (uses primary care data only, see note in script), ihd, myocardialinfarction, neuropathy, otherneuroconditions, pad, pulmonaryfibrosis, pulmonaryhypertension, retinopathy, revasc, rheumatoidarthritis, solid_cancer, solidorgantransplant, stroke, tia, primary_hhf (hospitalisation for HF with HF as primary cause), anxiety_disorders, medspecific_gi (from genital_infection codelist), unspecific_gi (from genital_infection_nonspec medcodelist and definite_genital_infection_meds prodcodelist), benignprostatehyperplasia, micturition_control, volume_depletion, urinary_frequency, falls, lowerlimbfracture, fluvacc (from fluvacc_stopflu_med and fluvacc_stopflu_prod codelists, courtesy of the STOPflu project), dka (HES only), amputation (from hosp_cause_majoramputation and hosp_cause_minoramputation; both in HES only and not just primary cause), osteoporosis, unstable angina (HES only).

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description |
| --- | --- |
| predrug_{comorbidity} | binary 0/1 if any instance of comorbidity before/at dstartdate |
| predrug_earliest_{comorbidity} | earliest occurrence of comorbidity before/at dstartdate |
| predrug_latest_{comorbidity} | latest occurrence of comorbidity before/at dstartdate |
| postdrug_first_{comorbidity} | earliest occurrence of comorbidity after (not at) dstartdate |
| postdrug_first_{comorbidity}\_gp_only | earliest occurrence of comorbidity after (not at) dstartdate, from GP (primary care) codes only |
| not present for unspecific_gi comorbidity |
| postdrug_first_{comorbidity}\_hes_icd10_only | earliest occurrence of comorbidity after (not at) dstartdate, from HES (secondary care) ICD10 (diagnosis) codes only |
| not present for unspecific_gi comorbidity |
| postdrug_first_{comorbidity}\_hes_opcs4_only | earliest occurrence of comorbidity after (not at) dstartdate, from HES (secondary care) OPCS4 (operation) codes only |
| not present for unspecific_gi comorbidity |
| hosp_admission_prev_year | 1 if patient has 1 or more hospital admision in the previous year to drug start (not including dstartdate).<br />NA if no admissions or if HES data not available - changed to 0 if no admissions and HES data available in final merge script |
| postdrug_first_all_cause_hosp | earliest inpatient hospital admission after (not at) dstartdate - emegency only (excluding admimeth=11, 12, or 13) |

&nbsp;

## Script: 05_mm_ckd_stages
### Table: mm_ckd_stages

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| preckdstage | CKD stage at baseline | CKD stages calculated as per [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#ckd-chronic-kidney-disease-stage)<br />eGFR calculated from creatinine using CKD-EPI creatinine 2021 equation<br />Start date = earliest test for CKD stage, only including those confirmed by another test at least 91 days later, without a test for a different stage in the intervening period<br />Baseline stage = maximum stage with start date < dstartdate or up to 7 days afterwards<br />CKD5 supplemented by medcodes/ICD10/OPCS4 codes for CKD5 / ESRD |
| preckdstagedate | date of onset of baseline CKD stage (earliest test for this stage) | |
| preckdstagedrugdiff | days between dstartdate and preckdstagedate | |
| postckdstage5date | date of onset of CKD stage 5 if occurs post-drug start (more than 7 days after drug start as baseline goes up to 7 days after drug start) | |
| postckdstage345date | date of onset of CKD stage 3a-5 if occurs post-drug start (more than 7 days after drug start as baseline goes up to 7 days after drug start) | |

&nbsp;

## Script: 06_mm_non_diabetes_meds
### Table: mm_non_diabetes_meds

Medications included currently:ACE-inhibitors, beta-blockers, calcium-channel blockers, thiazide-like diuretics (all BP meds), loop diuretics, potassium-sparing duiretics, definite genital infection meds (used in unspecific_gi comorbiditiy - see comorbidity script and table), prodspecific_gi (from topical candidal meds codelist), immunosuppressants, oral steriods, oestrogens, statins, fluvacc_stopflu_prod (used in combination with medcodes - see comorbidities script and table).

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description |
| --- | --- |
| predrug_earliest_{med} | earliest script for non-diabetes medication before/at dstartdate |
| predrug_latest_{med} | latest script for non-diabetes medication before/at dstartdate |
| postdrug_first_{med} | earliest script for non-diabetes medication after (not at) dstartdate |

&nbsp;

## Script: 07_mm_smoking
### Table: mm_smoking

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| smoking_cat | Smoking category at drug start: Non-smoker, Ex-smoker or Active smoker | Derived from [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#smoking) |
| qrisk2_smoking_cat | QRISK2 smoking category code (0-4) | |
| qrisk2_smoking_cat_uncoded | Decoded version of qrisk2_smoking_cat: 0=Non-smoker, 1= Ex-smoker, 2=Light smoker, 3=Moderate smoker, 4=Heavy smoker | |

&nbsp;

## Script: 08_mm_discontinuation
### Table: mm_discontinuation

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| ttc3m | 1 if timeondrug<=3 months | |
| ttc6m | 1 if timeondrug<=6 months (may also be <=3 months) | |
| ttc12m | 1 if timeondrug<=12 months (may also be <=6 months/3 months) | |
| stopdrug3m_3mFU | 1 if discontinue within 3 months and have at least 3 months followup to confirm this<br />0 if don't discontinue at 3 months | Followup time is time between last prescription of any glucose lowering medication and last prescription of this particular drug (the one they are discontinuing)<br /><br />These variables are missing if either a) the person does discontinue in the time period stated, but there is another glucose-lowering medication added or removed before this discontinuation, OR b) the person does discontinue in the time period stated, but the discontinuation represents a break int he current medication before restarting, OR c) the person does discontinue in the time stated, but does not have the followup time stated to confirm this |
| stopdrug3m_6mFU | 1 if discontinue within 3 months and have at least 6 months followup to confirm this<br />0 if don't discontinue at 3 months | |
| stopdrug6m_3mFU | 1 if discontinue within 6 months and have at least 3 months followup to confirm this<br />0 if don't discontinue at 6 months | |
| stopdrug6m_6mFU | 1 if discontinue within 6 months and have at least 6 months followup to confirm this<br />0 if don't discontinue at 6 months | |
| stopdrug12m_3mFU | 1 if discontinue within 12 months and have at least 3 months followup to confirm this<br />0 if don't discontinue at 12 months | |
| stopdrug12m_6mFU | 1 if discontinue within 12 months and have at least 6 months followup to confirm this<br />0 if don't discontinue at 12 months | |

&nbsp;

## Script: 09_mm_death_cause
### Table: mm_death_cause

1 line per patid for all patids in ONS death table

| Variable name | Description |
| --- | --- |
| primary_death_cause | primary death cause from ONS data (ICD10; 'cause' in ONS death table) |
| secondary_death_cause1-15 | secondary death cases from ONS data (ICD10; 'cause1'-'cause15' in ONS death table) |
| cv_death_primary | 1 if primary cause of death is CV |
| cv_death_any | 1 if any (primary or secondary) cause of death is CV |
| hf_death_primary | 1 if primary cause of death is heart failure |
| hf_death_any | 1 if any (primary or secondary) cause of death is heartfailure |

&nbsp;

## Script: 10_mm_final_merge
### Table: mm_{today's date}\_t2d_1stinstance

1 line per patid / drug class instance (continuous period of drug class use), but first instance (druginstance==1) drug periods only, and excludes those starting within 91 days of registration

Only includes patids with Type 2 diabetes in Type 1/2 cohort and with HES linkage (with_hes==1; see below all_t1t2_cohort table)

Adds in variables from other scripts (e.g. comorbidities, non-diabetes meds), and adds some additional ones (below)

| Variable name | Description |
| --- | --- |
| dstartdate_age | age at dstartdate in years (dstartdate-dob) |
| dstartdate_dm_dur_all | diabetes duration at dstartdate in years (dstartdate-dm_diag_date_all)<br />No missingness |
| dstartdate_dm_dur | diabetes duration at dstartdate in years (dstartdate-dm_diag_date)<br />Missing if diabetes diagnosis date is <91 days following registration (i.e. dm_diag_flag==1), as final merge script sets dm_diag_date to missing where this is the case - this is the only reason why this variable would be missing |
| qdiabeteshf_5yr_score | 5-year QDiabetes-heart failure score (in %)<br />Missing for anyone with age/BMI/biomarkers outside of range for model (or missing HbA1c or smoking info)<br />NB: NOT missing if have pre-existing HF but obviously not valid |
| qdiabeteshf_lin_predictor | QDiabetes heart failure linear predictor<br />Missing for anyone with age/BMI/biomarkers outside of range for model (or missing HbA1c or smoking info)<br />NB: NOT missing if have pre-existing HF but obviously not valid |
| qrisk2_5yr_score | 5-year QRISK2-2017 score (in %)<br />Missing for anyone with age/BMI/biomarkers outside of range for model (or missing smoking info)<br />NB: NOT missing if have CVD but obviously not valid |
| qrisk2_10yr_score | 10-year QRISK2-2017 score (in %)<br />Missing for anyone with age/BMI/biomarkers outside of range for model (or missing smoking info)<br />NB: NOT missing if have CVD but obviously not valid |
| qrisk2_lin_predictor | QRISK2-2017 linear predictor<br />NB: NOT missing if have CVD but obviously not valid<br />Missing for anyone with age/BMI/biomarkers outside of range for model (or missing smoking info) |
| ckdpc_egfr60_total_score | CKDPC risk score for 5-year risk of eGFR<=60ml/min/1.73m2 in people with diabetes (total events). <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 at drug start (but not if missing eGFR), with age/BMI/biomarkers outside of range for model, or missing any predictors (ethnicity, eGFR, HbA1c, smoking info, BMI or UACR) |
| ckdpc_egfr60_total_lin_predictor | Linear predictor for CKDPC risk score for eGFR<=60ml/min/1.73m2 in people with diabetes (total events). <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 at drug start (but not if missing eGFR), with age/BMI/biomarkers outside of range for model, or missing any predictors (ethnicity, eGFR, HbA1c, smoking info, BMI or UACR) |
| ckdpc_egfr60_confirmed_score | CKDPC risk score for 5-year risk of eGFR<=60ml/min/1.73m2 in people with diabetes (confirmed events only). <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 at drug start (but not if missing eGFR), with age/BMI/biomarkers outside of range for model, or missing any predictors (ethnicity, eGFR, HbA1c, smoking info, BMI or UACR) |
| ckdpc_egfr60_confirmed_lin_predictor | Linear predictor for CKDPC risk score for eGFR<=60ml/min/1.73m2 in people with diabetes (confirmed events). <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 at drug start (but not if missing eGFR), with age/BMI/biomarkers outside of range for model, or missing any predictors (ethnicity, eGFR, HbA1c, smoking info, BMI or UACR) |
| ckdpc_40egfr_score | CKDPC risk score for 3-year risk of 40% decline in eGFR or kidney failure in people with diabetes and baseline eGFR>=60ml/min/1.73m2. <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 at drug start (but not if missing eGFR), with age/BMI/biomarkers outside of range for model, or missing any predictors (eGFR, HbA1c, smoking info, SBP, BMI or UACR) |
| ckdpc_40egfr_lin_predictor | Linear predictor for CKDPC risk score for 40% decline in eGFR or kidney failure in people with diabetes and baseline eGFR>=60ml/min/1.73m2. <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 (but not if missing eGFR) at drug start, with age/BMI/biomarkers outside of range for model, or missing any predictors (eGFR, HbA1c, smoking info, SBP, BMI or UACR) |

&nbsp;

## Script: all_patid_ethnicity_table
### Table: all_patid_ethnicity

1 line per patid in download

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| ethnicity_5cat | 5-category ethnicity: (0=White, 1=South Asian, 2=Black, 3=Other, 4=Mixed) | Uses [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#ethnicity) (NB: use all medcodes; no date restrictions):<br />Use most frequent category<br />If multiple categories with same frequency, use latest one<br />If multiple categories with same frequency and used as recently as each other, label as missing<br />Use HES if missing/no consensus from medcodes |
| ethnicity_16cat | 16-category ethnicity: (1=White British, 2=White Irish, 3=Other White, 4=White and Black Caribbean, 5=White and Black African, 6=White and Asian, 7=Other Mixed, 8=Indian, 9=Pakistani, 10=Bangladeshi, 11=Other Asian, 12=Caribbean, 13=African, 14=Other Black, 15=Chinese, 16=Other) | |
| ethnicity_qrisk2 | QRISK2 ethnicity category: (1=White, 2=Indian, 3=Pakistani, 4=Bangladeshi, 5=Other Asian, 6=Black Caribbean, 7=Black African, 8=Chinese, 9=Other) | |

&nbsp;

## Script: all_patid_townsend_deprivation_score
### Table: all_patid_townsend

1 line per patid with Index of Multiple Deprivation Score from CPRD

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| imd2015_10 | English Index of Multiple Deprivation (IMD) decile (1=most deprived, 10=least deprived) | |
| tds_2011 | Townsend Deprivation Score (TDS) - made by converting IMD decile scores (median TDS for LSOAs with the same IMD decile as patient used) | See [algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#townsend-deprivation-scores) |

&nbsp;

## Script: all_t1t2_cohort_table
### Table: all_t1t2_cohort

1 line per patid who meet requirements for being in Type 1/2 cohort

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| gender | gender (1=male, 2=female) | |
| dob | date of birth | if month and date missing, 1st July used, if date but not month missing, 15th of month used, or earliest medcode in year of birth if this is earlier |
| pracid | practice ID | |
| prac_region | practice region: 1=North East, 2=North West, 3=Yorkshire And The Humber, 4=East Midlands, 5=West Midlands, 6=East of England, 7=South West, 8=South Central, 9=London, 10=South East Coast, 11 Northern Ireland, 12 Scotland, 13 Wales | |
| has_insulin | has a prescription for insulin ever (excluding invalid dates - before DOB / after LCD/death/deregistration) | |
| type1_code_count | number of Type 1-specific codes in records (any date) | |
| type2_code_count | number of Type 2-specific codes in records (any date) | |
| dm_diag_dmcodedate | earliest diabetes medcode (excluding those with obstypeid=4 (family history) and invalid dates) | |
| dm_diag_hba1cdate | earliest HbA1c >47.5 mmol/mol (excluding invalid dates, including those with valid value and unit codes only) | |
| dm_diag_ohadate | earliest OHA prescription (excluding invalid dates) | |
| dm_diag_insdate | earliest insulin prescription (excluding invalid dates) | |
| dm_diag_date_all / dm_diag_date | diabetes diagnosis date<br />dm_diag_date_all is not missing for anyone<br />In final merge script, 'dm_diag_date' is the same as 'dm_diag_date_all' except it is set to missing if diabetes diagnosis date is <91 days following registration (i.e. dm_diag_flag==1) - this is the only reason why this variable would be missing | earliest of dm_diag_dmcodedate, dm_diag_hba1cdate, dm_diag_ohadate, and dm_diag_insdate.<br />It's worth noting that we have a number of people classified as Type 2 who appear to have been diagnosed at a young age, which is likely to be a coding error. This small proportion shouldn't affect Mastermind analysis results greatly, but might need to be considered for other analysis |
| dm_diag_codetype | whether diagnosis date represents diabetes medcode (1), high HbA1c (2), OHA prescription (3) or insulin (4) - if multiple on same day, use lowest number | |
| dm_diag_flag | whether diagnosis date is <91 days following registration | |
| dm_diag_age_all / dm_diag_age | age at diabetes diagnosis<br />dm_diag_age_all is not missing for anyone<br />In final merge script, 'dm_diag_age' is the same as 'dm_diag_age_all' except it is set to missing if diabetes diagnosis date is <91 days following registration (i.e. dm_diag_flag==1) - this is the only reason why this variable would be missing | dm_diag_date - dob<br />See above note next to dm_diag_date_all variable on young diagnosis in T2Ds |
| dm_diag_before_reg | whether diagnosed before registration | |
| ins_in_1_year | whether started insulin within 1 year of diagnosis (**0 may mean no or missing**) | |
| current_oha | whether prescription for insulin within last 6 months of data | last 6 months of data = those before LCD/death/deregistration |
| diabetes_type | diabetes type | See [algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#diabetes-algorithms)<br />NB: we now have a few 'unclassified's - not included in any T2D cohorts. Date/age of diagnosis, time to insulin from diagnosis, and whether diagnosis is before registration is likely to be unreliable for these people.<br />See above note next to dm_diag_date_all variable on young diagnosis in T2Ds |
| regstartdate | registration start date | |
| gp_record_end | earliest of last collection date from practice, deregistration and 31/10/2020 (latest date in records) | |
| death_date | earliest of 'cprddeathdate' (derived by CPRD) and ONS death date | NA if no death date |
| with_hes | 1 for patients with HES linkage and n_patid_hes<=20, otherwise 0<br />In final merge script - usually exclude people where with_hes==0 | |
