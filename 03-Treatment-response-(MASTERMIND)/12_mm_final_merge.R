
# Extract dataset of all first instance drug periods (i.e. the first time patient has taken this particular drug class) for ALL DIABETES/T2Ds, regardless of linkage
## Exclude drug periods starting within 90 days of registration
## Exclude drug periods after death
## Set drugline to missing where diagnosed before registration

## Do not exclude where first line
## Do not exclude where patient is on insulin at drug initiation
## Do not exclude where only 1 prescription (dstartdate=dstopdate)

## Set hosp_admission_prev_year to 0/1 rather than NA/1

# Also extract all drug start and stop dates so that you can see if people later initiate SGLT2is/GLP1s etc.


############################################################################################

# Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024", cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("mm")


############################################################################################

# Today's date for table names

today <- format(Sys.Date(), "%Y%m%d")


############################################################################################

# Get handles to pre-existing data tables

## Cohort and patient characteristics including Townsend scores and death causes
analysis = cprd$analysis("all")
diabetes_cohort <- diabetes_cohort %>% analysis$cached("diabetes_cohort")
townsend_score <- townsend_score %>% analysis$cached("patid_townsend_score")
death_causes <- death_causes %>% analysis$cached("death_causes")

## Drug info
analysis = cprd$analysis("mm")
drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")
combo_start_stop <- combo_start_stop %>% analysis$cached("combo_start_stop")

## Biomarkers inc. CKD
#baseline_biomarkers <- baseline_biomarkers %>% analysis$cached("baseline_biomarkers")
response_biomarkers <- response_biomarkers %>% analysis$cached("response_biomarkers") #includes baseline biomarker values for first instance drug periods so no need to use baseline_biomakers table
ckd_stages <- ckd_stages %>% analysis$cached("ckd_stages")

## Comorbidities and eFI
comorbidities <- comorbidities %>% analysis$cached("comorbidities")
efi <- efi %>% analysis$cached("efi")

## Non-diabetes meds
non_diabetes_meds <- non_diabetes_meds %>% analysis$cached("non_diabetes_meds")

## Smoking status at drug start
smoking <- smoking %>% analysis$cached("smoking")

#Alcohol at drug start
alcohol <- alcohol %>% analysis$cached("alcohol")

## Discontinuation
discontinuation <- discontinuation %>% analysis$cached("discontinuation")

## Glycaemic failure
glycaemic_failure <- glycaemic_failure %>% analysis$cached("glycaemic_failure")


############################################################################################

# Make first instance drug period dataset

## Define all diabetes cohort (1 line per patient)
## Add in Townsend Deprivation Scores
all_diabetes <- diabetes_cohort %>%
  left_join((townsend_score %>% select(patid, tds_2011)), by="patid") %>%
  relocate(tds_2011, .after=imd_decile)


## Get info for first instance drug periods for cohort (1 line per patid-drug_substance period)
### Make new drugline variable which is missing where diagnosed before registration or within 90 days following

all_diabetes_drug_periods <- all_diabetes %>%
  inner_join(drug_start_stop, by="patid") %>%
  inner_join(combo_start_stop, by=c("patid", c("dstartdate"="dcstartdate"))) %>%
  mutate(drugline=ifelse(dm_diag_date_all<regstartdate | is.na(dm_diag_date), NA, drugline_all)) %>%
  relocate(drugline, .after=drugline_all) %>%
  analysis$cached(paste0(today, "_all_1stinstance_interim_1"), indexes=c("patid", "dstartdate", "drug_class", "drug_substance"))

all_diabetes_drug_periods %>% distinct(patid) %>% count()
# 1,752,846
  

### Keep first instance only
all_diabetes_1stinstance <- all_diabetes_drug_periods %>%
  filter(drug_instance==1)

all_diabetes_1stinstance %>% distinct(patid) %>% count()
# 1,752,846 as above


### Exclude drug periods starting within 90 days of registration
all_diabetes_1stinstance <- all_diabetes_1stinstance %>%
  filter(datediff(dstartdate, regstartdate)>90)

all_diabetes_1stinstance %>% count()
# 3,004,907

all_diabetes_1stinstance %>% distinct(patid) %>% count()
# 1,346,921


### Exclude drug periods starting after or on same day as death
all_diabetes_1stinstance <- all_diabetes_1stinstance %>%
  filter(is.na(death_date) | death_date>dstartdate)

all_diabetes_1stinstance %>% count()
# 3,004,813

all_diabetes_1stinstance %>% distinct(patid) %>% count()
# 1,346,887


## Merge in biomarkers, comorbidities, eFI, non-diabetes meds, smoking status, alcohol
### Could merge on druginstance too, but quicker not to
### Remove some variables to avoid duplicates
### Now in two stages to speed it up

all_diabetes_1stinstance <- all_diabetes_1stinstance %>%
  inner_join((response_biomarkers %>% select(-c(drug_class, drug_instance, timeprevcombo_class))), by=c("patid", "dstartdate", "drug_substance")) %>%
  inner_join((ckd_stages %>% select(-c(drug_class, drug_instance))), by=c("patid", "dstartdate", "drug_substance")) %>%
  inner_join((comorbidities %>% select(-c(drug_class, drug_instance))), by=c("patid", "dstartdate", "drug_substance")) %>%
  inner_join((efi %>% select(-c(drug_class, drug_instance))), by=c("patid", "dstartdate", "drug_substance")) %>%
  analysis$cached(paste0(today, "_all_1stinstance_interim_2"), indexes=c("patid", "dstartdate", "drug_substance"))

all_diabetes_1stinstance <- all_diabetes_1stinstance %>%
  inner_join((non_diabetes_meds %>% select(-c(drug_class, drug_instance))), by=c("patid", "dstartdate", "drug_substance")) %>%
  inner_join((smoking %>% select(-c(drug_class, drug_instance))), by=c("patid", "dstartdate", "drug_substance")) %>%
  inner_join((alcohol %>% select(-c(drug_class, drug_instance))), by=c("patid", "dstartdate", "drug_substance")) %>%
  left_join(death_causes, by="patid") %>%
  mutate(hosp_admission_prev_year=ifelse(is.na(hosp_admission_prev_year) & with_hes==1, 0L,
                                         ifelse(hosp_admission_prev_year==1, 1L, NA)),
         hosp_admission_prev_year_count=ifelse(is.na(hosp_admission_prev_year_count) & with_hes==1, 0L, hosp_admission_prev_year_count)) %>%
  analysis$cached(paste0(today, "_all_1stinstance_interim_3"), indexes=c("patid", "dstartdate", "drug_substance"))


## Merge in glycaemic failure and discontinuation - both are currently by drug class (not substance) only
### Glycaemic failure doesn't include all drug periods - only those with HbA1cs
### Make new variables: age at drug start, diabetes duration at drug start

all_diabetes_1stinstance <- all_diabetes_1stinstance %>%
  left_join((glycaemic_failure %>% select(-c(dstopdate, timetochange, timetoaddrem, nextdrugchange, nextdcdate, prehba1c, prehba1cdate, threshold_7.5, threshold_8.5, threshold_baseline, threshold_baseline_0.5))), by=c("patid", "dstartdate", "drug_class")) %>%
  left_join((discontinuation %>% select(-c(drugline_all, dstopdate_class, drug_instance, timeondrug, nextremdrug, timetolastpx))), by=c("patid", "dstartdate"="dstartdate_class", "drug_class")) %>%
  mutate(dstartdate_age=datediff(dstartdate, dob)/365.25,
         dstartdate_dm_dur_all=datediff(dstartdate, dm_diag_date_all)/365.25,
         dstartdate_dm_dur=datediff(dstartdate, dm_diag_date)/365.25) %>%
  analysis$cached(paste0(today, "_all_1stinstance_interim_4"), indexes=c("patid", "dstartdate", "drug_substance"))
  

# Check counts

all_diabetes_1stinstance %>% count()
# 3,004,813

all_diabetes_1stinstance %>% distinct(patid) %>% count()
# 1,346,887


############################################################################################

# Add in 5 year QDiabetes-HF score and QRISK2 score

## Make separate table with additional variables for QRISK2 and QDiabetes-HF

qscore_vars <- all_diabetes_1stinstance %>%
  mutate(precholhdl=pretotalcholesterol/prehdl,
         ckd45=!is.na(preckdstage) & (preckdstage=="stage_4" | preckdstage=="stage_5"),
         cvd=predrug_myocardialinfarction==1 | predrug_angina==1 | predrug_stroke==1,
         sex=ifelse(gender==1, "male", ifelse(gender==2, "female", "NA")),
         dm_duration_cat=ifelse(dstartdate_dm_dur_all<=1, 0L,
                                ifelse(dstartdate_dm_dur_all<4, 1L,
                                       ifelse(dstartdate_dm_dur_all<7, 2L,
                                              ifelse(dstartdate_dm_dur_all<11, 3L, 4L)))),

         earliest_bp_med=pmin(
           ifelse(is.na(predrug_earliest_ace_inhibitors),as.Date("2050-01-01"),predrug_earliest_ace_inhibitors),
           ifelse(is.na(predrug_earliest_beta_blockers),as.Date("2050-01-01"),predrug_earliest_beta_blockers),
           ifelse(is.na(predrug_earliest_ca_channel_blockers),as.Date("2050-01-01"),predrug_earliest_ca_channel_blockers),
           ifelse(is.na(predrug_earliest_thiazide_diuretics),as.Date("2050-01-01"),predrug_earliest_thiazide_diuretics),
           na.rm=TRUE
         ),
         latest_bp_med=pmax(
           ifelse(is.na(predrug_latest_ace_inhibitors),as.Date("1900-01-01"),predrug_latest_ace_inhibitors),
           ifelse(is.na(predrug_latest_beta_blockers),as.Date("1900-01-01"),predrug_latest_beta_blockers),
           ifelse(is.na(predrug_latest_ca_channel_blockers),as.Date("1900-01-01"),predrug_earliest_ca_channel_blockers),
           ifelse(is.na(predrug_latest_thiazide_diuretics),as.Date("1900-01-01"),predrug_latest_thiazide_diuretics),
           na.rm=TRUE
         ),
         bp_meds=ifelse(earliest_bp_med!=as.Date("2050-01-01") & latest_bp_med!=as.Date("1900-01-01") & datediff(dstartdate, latest_bp_med)<=28 & earliest_bp_med!=latest_bp_med, 1L, 0L),

         type1=0L,
         type2=1L,
         surv_5yr=5L,
         surv_10yr=10L) %>%

  select(patid, dstartdate, drug_substance, sex, dstartdate_age, ethnicity_qrisk2, qrisk2_smoking_cat, dm_duration_cat, bp_meds, type1, type2, cvd, ckd45, predrug_fh_premature_cvd, predrug_af, predrug_rheumatoidarthritis, prehba1c2yrs, precholhdl, presbp, prebmi, tds_2011, surv_5yr, surv_10yr) %>%

  analysis$cached(paste0(today, "_all_1stinstance_interim_q1"), indexes=c("patid", "dstartdate", "drug_substance"))



## Calculate 5 year QDiabetes-HF and 5 year and 10 year QRISK2 scores
### For some reason it doesn't like collation of sex variable unless remake it

## Remove QDiabetes-HF score for those with biomarker values outside of range:
### CholHDL: missing or 1-11 (NOT 12)
### HbA1c: 40-150
### SBP: missing or 70-210
### Age: 25-84
### Also exclude if BMI<20 as v. different from development cohort

## Remove QRISK2 score for those with biomarker values outside of range:
### CholHDL: missing or 1-12
### SBP: missing or 70-210
### Age: 25-84
### Also exclude if BMI<20 as v. different from development cohort

qscores <- qscore_vars %>%

  mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%

  calculate_qdiabeteshf(sex=sex2, age=dstartdate_age, ethrisk=ethnicity_qrisk2, smoking=qrisk2_smoking_cat, duration=dm_duration_cat, type1=type1, cvd=cvd, renal=ckd45, af=predrug_af, hba1c=prehba1c2yrs, cholhdl=precholhdl, sbp=presbp, bmi=prebmi, town=tds_2011, surv=surv_5yr) %>%

  analysis$cached(paste0(today, "_all_1stinstance_interim_q2"), indexes=c("patid", "dstartdate", "drug_substance"))



qscores <- qscores %>%

  mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%

  calculate_qrisk2(sex=sex2, age=dstartdate_age, ethrisk=ethnicity_qrisk2, smoking=qrisk2_smoking_cat, type1=type1, type2=type2, fh_cvd=predrug_fh_premature_cvd, renal=ckd45, af=predrug_af, rheumatoid_arth=predrug_rheumatoidarthritis, cholhdl=precholhdl, sbp=presbp, bmi=prebmi, bp_med=bp_meds, town=tds_2011, surv=surv_5yr) %>%

  rename(qrisk2_score_5yr=qrisk2_score) %>%

  select(-qrisk2_lin_predictor) %>%

  analysis$cached(paste0(today, "_all_1stinstance_interim_q3"), indexes=c("patid", "dstartdate", "drug_substance"))



qscores <- qscores %>%

  mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%

  calculate_qrisk2(sex=sex2, age=dstartdate_age, ethrisk=ethnicity_qrisk2, smoking=qrisk2_smoking_cat, type1=type1, type2=type2, fh_cvd=predrug_fh_premature_cvd, renal=ckd45, af=predrug_af, rheumatoid_arth=predrug_rheumatoidarthritis, cholhdl=precholhdl, sbp=presbp, bmi=prebmi, bp_med=bp_meds, town=tds_2011, surv=surv_10yr) %>%


  mutate(qdiabeteshf_5yr_score=ifelse((is.na(precholhdl) | (precholhdl>=1 & precholhdl<=11)) &
                                        prehba1c2yrs>=40 & prehba1c2yrs<=150 &
                                        (is.na(presbp) | (presbp>=70 & presbp<=210)) &
                                        dstartdate_age>=25 & dstartdate_age<=84 &
                                        (is.na(prebmi) | prebmi>=20), qdiabeteshf_score, NA),

         qdiabeteshf_lin_predictor=ifelse((is.na(precholhdl) | (precholhdl>=1 & precholhdl<=11)) &
                                            prehba1c2yrs>=40 & prehba1c2yrs<=150 &
                                                (is.na(presbp) | (presbp>=70 & presbp<=210)) &
                                                dstartdate_age>=25 & dstartdate_age<=84 &
                                            (is.na(prebmi) | prebmi>=20), qdiabeteshf_lin_predictor, NA),

         qrisk2_5yr_score=ifelse((is.na(precholhdl) | (precholhdl>=1 & precholhdl<=12)) &
                                    (is.na(presbp) | (presbp>=70 & presbp<=210)) &
                                    dstartdate_age>=25 & dstartdate_age<=84 &
                                   (is.na(prebmi) | prebmi>=20), qrisk2_score_5yr, NA),

         qrisk2_10yr_score=ifelse((is.na(precholhdl) | (precholhdl>=1 & precholhdl<=12)) &
                                   (is.na(presbp) | (presbp>=70 & presbp<=210)) &
                                   dstartdate_age>=25 & dstartdate_age<=84 &
                                    (is.na(prebmi) | prebmi>=20), qrisk2_score, NA),

         qrisk2_lin_predictor=ifelse((is.na(precholhdl) | (precholhdl>=1 & precholhdl<=12)) &
                                            (is.na(presbp) | (presbp>=70 & presbp<=210)) &
                                            dstartdate_age>=25 & dstartdate_age<=84 &
                                       (is.na(prebmi) | prebmi>=20), qrisk2_lin_predictor, NA)) %>%

  select(patid, dstartdate, drug_substance, qdiabeteshf_5yr_score, qdiabeteshf_lin_predictor, qrisk2_5yr_score, qrisk2_10yr_score, qrisk2_lin_predictor) %>%

  analysis$cached(paste0(today, "_all_1stinstance_interim_q4"), indexes=c("patid", "dstartdate", "drug_substance"))



## Join with main dataset

all_diabetes_1stinstance <- all_diabetes_1stinstance %>%
  left_join(qscores, by=c("patid", "dstartdate", "drug_substance")) %>%
  analysis$cached(paste0(today, "_all_1stinstance_interim_5"), indexes=c("patid", "dstartdate", "drug_substance"))


############################################################################################

# # Add in kidney risk scores
# 
# ## Make separate table with additional variables
# 
# ckdpc_score_vars <- all_diabetes_1stinstance %>%
#   
#   mutate(sex=ifelse(gender==1, "male", ifelse(gender==2, "female", "NA")),
#          
#          black_ethnicity=ifelse(!is.na(ethnicity_5cat) & ethnicity_5cat==2, 1L, ifelse(is.na(ethnicity_5cat), NA, 0L)),
#          
#          cvd=predrug_myocardialinfarction==1 | predrug_revasc==1 | predrug_heartfailure==1 | predrug_stroke==1,
#          
#          oha=ifelse(Acarbose+MFN+DPP4+Glinide+GLP1+SGLT2+SU+TZD>add, 1L, 0L),
#          
#          ever_smoker=ifelse(!is.na(smoking_cat) & (smoking_cat=="Ex-smoker" | smoking_cat=="Active smoker"), 1L, ifelse(is.na(smoking_cat), NA, 0L)),
#          
#          latest_bp_med=pmax(
#            ifelse(is.na(predrug_latest_ace_inhibitors), as.Date("1900-01-01"), predrug_latest_ace_inhibitors),
#            ifelse(is.na(predrug_latest_beta_blockers), as.Date("1900-01-01"), predrug_latest_beta_blockers),
#            ifelse(is.na(predrug_latest_calcium_channel_blockers), as.Date("1900-01-01"), predrug_latest_calcium_channel_blockers),
#            ifelse(is.na(predrug_latest_thiazide_diuretics), as.Date("1900-01-01"), predrug_latest_thiazide_diuretics),
#            na.rm=TRUE
#          ),
#          
#          bp_meds=ifelse(latest_bp_med!=as.Date("1900-01-01") & datediff(dstartdate, latest_bp_med)<=183, 1L, 0L),
#          
#          hypertension=ifelse((!is.na(presbp) & presbp>=140) | (!is.na(predbp) & predbp>=90) | bp_meds==1, 1L,0L),
#          
#          uacr=ifelse(!is.na(preacr), preacr, ifelse(!is.na(preacr_from_separate), preacr_from_separate, NA)),
#          
#          chd=predrug_myocardialinfarction==1 | predrug_revasc==1,
#          
#          current_smoker=ifelse(!is.na(smoking_cat) & smoking_cat=="Active smoker", 1L, ifelse(is.na(smoking_cat), NA, 0L)),
#          
#          ex_smoker=ifelse(!is.na(smoking_cat) & smoking_cat=="Ex-smoker", 1L, ifelse(is.na(smoking_cat), NA, 0L))) %>%
#   
#   select(patid, dstartdate, drugclass, dstartdate_age, sex, black_ethnicity, preegfr, cvd, prehba1c2yrs, INS, oha, ever_smoker, hypertension, prebmi, uacr, presbp, bp_meds, predrug_heartfailure, chd, predrug_af, current_smoker, ex_smoker, preckdstage) %>%
#   
#   analysis$cached(paste0(today, "_all_1stinstance_interim_ckd1"), indexes=c("patid", "dstartdate", "drugclass"))
# 
# 
# 
# ### Calculate CKD risk score (5-year eGFR<60 risk + 3-year 40% decline in eGFR/renal failure)
# ### For some reason it doesn't like collation of sex variable unless remake it
# 
# ## Remove for either if eGFR<60 (have only coded up version of second model for those with eGFR>=60)
# 
# ## Also remove eGFR<60 score for those with biomarker values outside of range:
# ### Age: 20-80
# ### UACR: 0.6-56.5 (5-500 in mg/g)
# ### BMI: 20-40
# ### HbA1c 42-97 (6-11 in %)
# 
# ## Also remove 40% decline in eGFR score for those with biomarker values outside of range:
# ### Age: 20-80
# ### UACR: 0.6-113 (5-1000 in mg/g)
# ### SBP: 80-180
# ### BMI: 20-40
# ### HbA1c 42-97 (6-11 in %)
# 
# ckdpc_scores <- ckdpc_score_vars %>%
#   
#   mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%
#   
#   calculate_ckdpc_egfr60_risk(age=dstartdate_age, sex=sex2, black_eth=black_ethnicity, egfr=preegfr, cvd=cvd, hba1c=prehba1c2yrs, insulin=INS, oha=oha, ever_smoker=ever_smoker, hypertension=hypertension, bmi=prebmi, acr=uacr, complete_acr=TRUE, remote=TRUE) %>%
#   
#   rename(ckdpc_egfr60_total_score_complete_acr=ckdpc_egfr60_total_score, ckdpc_egfr60_total_lin_predictor_complete_acr=ckdpc_egfr60_total_lin_predictor, ckdpc_egfr60_confirmed_score_complete_acr=ckdpc_egfr60_confirmed_score, ckdpc_egfr60_confirmed_lin_predictor_complete_acr=ckdpc_egfr60_confirmed_lin_predictor) %>%
#   
#   analysis$cached(paste0(today, "_all_1stinstance_interim_ckd2"), indexes=c("patid", "dstartdate", "drugclass"))
# 
# 
# 
# ckdpc_scores <- ckdpc_scores %>%
#   
#   mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%
#   
#   calculate_ckdpc_egfr60_risk(age=dstartdate_age, sex=sex2, black_eth=black_ethnicity, egfr=preegfr, cvd=cvd, hba1c=prehba1c2yrs, insulin=INS, oha=oha, ever_smoker=ever_smoker, hypertension=hypertension, bmi=prebmi, acr=uacr, remote=TRUE) %>%
#   
#   analysis$cached(paste0(today, "_all_1stinstance_interim_ckd3"), indexes=c("patid", "dstartdate", "drugclass"))
# 
# 
# 
# ckdpc_scores <- ckdpc_scores %>%
#   
#   mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%
#   
#   calculate_ckdpc_40egfr_risk(age=dstartdate_age, sex=sex2, egfr=preegfr, acr=uacr, sbp=presbp, bp_meds=bp_meds, hf=predrug_heartfailure, chd=chd, af=predrug_af, current_smoker=current_smoker, ex_smoker=ex_smoker, bmi=prebmi, hba1c=prehba1c2yrs, oha=oha, insulin=INS, remote=TRUE) %>%
#   
#   mutate(across(starts_with("ckdpc_egfr60"),
#                 ~ifelse((is.na(preckdstage) | preckdstage=="stage_1" | preckdstage=="stage_2") &
#                           (is.na(preegfr) | preegfr>=60) &
#                           dstartdate_age>=20 & dstartdate_age<=80 &
#                           prebmi>=20, .x, NA))) %>%
#   
#   mutate(across(starts_with("ckdpc_40egfr"),
#                 ~ifelse((is.na(preckdstage) | preckdstage=="stage_1" | preckdstage=="stage_2") &
#                           (is.na(preegfr) | preegfr>=60) &
#                           dstartdate_age>=20 & dstartdate_age<=80 &
#                           prebmi>=20, .x, NA))) %>%
#   
#   select(patid, dstartdate, drugclass, ckdpc_egfr60_total_score_complete_acr, ckdpc_egfr60_total_lin_predictor_complete_acr, ckdpc_egfr60_confirmed_score_complete_acr, ckdpc_egfr60_confirmed_lin_predictor_complete_acr, ckdpc_egfr60_total_score, ckdpc_egfr60_total_lin_predictor, ckdpc_egfr60_confirmed_score, ckdpc_egfr60_confirmed_lin_predictor, ckdpc_40egfr_score, ckdpc_40egfr_lin_predictor) %>%
#   
#   analysis$cached(paste0(today, "_all_1stinstance_interim_ckd4"), indexes=c("patid", "dstartdate", "drugclass"))
# 
# 
# 
# ## Join with main dataset
# 
# all_diabetes_1stinstance <- all_diabetes_1stinstance %>%
#   left_join(ckdpc_scores, by=c("patid", "dstartdate", "drugclass")) %>%
#   analysis$cached(paste0(today, "_all_diabetes_1stinstance"), indexes=c("patid", "dstartdate", "drugclass"))


############################################################################################

## Filter just type 2s
t2d_1stinstance <- all_diabetes_1stinstance %>% filter(diabetes_type=="type 2") %>%
  analysis$cached(paste0(today, "_t2d_1stinstance"), indexes=c("patid", "dstartdate", "drug_class", "drug_substance"))

### Check unique patid count
t2d_1stinstance %>% distinct(patid) %>% count()
#1,269,977


############################################################################################

# Make dataset of all drug starts so that can see whether people later initiate SGLT2i/GLP1 etc.
## Not cleaned to remove those close to reg start / after death

## Just T2s
t2d_all_drug_periods <- all_diabetes %>%
  filter(diabetes_type=="type 2") %>%
  select(patid) %>%
  inner_join(drug_start_stop, by="patid") %>%
  analysis$cached(paste0(today, "_t2d_all_drug_periods"))

