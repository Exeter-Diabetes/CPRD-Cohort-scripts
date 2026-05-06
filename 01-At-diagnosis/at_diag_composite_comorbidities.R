

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd <- CPRDData$new(cprdEnv = "diabetes-jun2024", cprdConf = "~/.aurum.yaml")

###############################################################################

# Get index dates for patients
analysis <- cprd$analysis("all")
diabetes_cohort <- diabetes_cohort %>% analysis$cached("diabetes_cohort")

index_dates <- diabetes_cohort %>%
  filter(!is.na(dm_diag_date)) %>%
  select(patid, index_date = dm_diag_date)


# Load comorbidities
analysis <- cprd$analysis("at_diag")
comorbidities <- comorbidities %>% analysis$cached("comorbidities")

###############################################################################


################################################################################

# Retinopathy

# Join index dates with retinopathy complications
retinopathy_severity <- index_dates %>%
  left_join(
    comorbidities %>% select(
      "patid",
      "index_date",
      "pre_index_date_earliest_non_severe_retinopathy", 
      "pre_index_date_latest_non_severe_retinopathy",
      "pre_index_date_non_severe_retinopathy",
      "post_index_date_first_non_severe_retinopathy",
      "pre_index_date_earliest_vitreous_and_pre_retinal_haemorrhage",
      "pre_index_date_latest_vitreous_and_pre_retinal_haemorrhage",
      "pre_index_date_vitreous_and_pre_retinal_haemorrhage",
      "post_index_date_first_vitreous_and_pre_retinal_haemorrhage", 
      "pre_index_date_earliest_proliferative_retinopathy", 
      "pre_index_date_latest_proliferative_retinopathy",
      "pre_index_date_proliferative_retinopathy",
      "post_index_date_first_proliferative_retinopathy", 
      "pre_index_date_earliest_blindness_and_visual_impairment",
      "pre_index_date_blindness_and_visual_impairment",
      "post_index_date_first_blindness_and_visual_impairment",
      ), by = c("patid","index_date")
  )
  

            
# Create severe_retinopathy composite and create pre and post flags/dates
retinopathy_severity <- retinopathy_severity %>%
  mutate(
    
    ## --- Non-severe retinopathy ---
    
    # Create post flag 
    post_index_date_non_severe_retinopathy =
      as.integer(!is.na(post_index_date_first_non_severe_retinopathy)),
    
    ## --- Severe retinopathy (composite) ---
    #  - vitreous_and_pre_retinal_haemorrhage 
    #  - proliferative_retinopathy (includes photocoagulation)
    #  - blindness_and_visual_impairment
    # PRE: earliest severe retinopathy
    pre_index_date_earliest_severe_retinopathy = pmin(
      if_else(!is.na(pre_index_date_earliest_vitreous_and_pre_retinal_haemorrhage),
              pre_index_date_earliest_vitreous_and_pre_retinal_haemorrhage,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_proliferative_retinopathy),
              pre_index_date_earliest_proliferative_retinopathy,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_blindness_and_visual_impairment),
              pre_index_date_earliest_blindness_and_visual_impairment,
              as.Date("2050-01-01")),
      na.rm = TRUE
    ),
    
    
    # PRE: latest severe retinopathy
    pre_index_date_latest_severe_retinopathy = pmax(
      if_else(!is.na(pre_index_date_latest_vitreous_and_pre_retinal_haemorrhage),
              pre_index_date_latest_vitreous_and_pre_retinal_haemorrhage,
              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_latest_proliferative_retinopathy),
              pre_index_date_latest_proliferative_retinopathy,
              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_earliest_blindness_and_visual_impairment),
              pre_index_date_earliest_blindness_and_visual_impairment,
              as.Date("1900-01-01")),
      na.rm = TRUE
    ),
    
    # Convert back to NA
    pre_index_date_earliest_severe_retinopathy =
      if_else(pre_index_date_earliest_severe_retinopathy == as.Date("2050-01-01"),
              as.Date(NA), pre_index_date_earliest_severe_retinopathy),
    
    pre_index_date_latest_severe_retinopathy =
      if_else(pre_index_date_latest_severe_retinopathy == as.Date("1900-01-01"),
              as.Date(NA), pre_index_date_latest_severe_retinopathy),
    
    # PRE flag
    pre_index_date_severe_retinopathy =
      as.integer(!is.na(pre_index_date_earliest_severe_retinopathy)),
    
    
    # POST: first severe retinopathy after diagnosis
    post_index_date_first_severe_retinopathy = pmin(
      if_else(!is.na(post_index_date_first_vitreous_and_pre_retinal_haemorrhage),
              post_index_date_first_vitreous_and_pre_retinal_haemorrhage,
              as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_proliferative_retinopathy),
              post_index_date_first_proliferative_retinopathy,
              as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_blindness_and_visual_impairment),
              post_index_date_first_blindness_and_visual_impairment,
              as.Date("2050-01-01")),
      na.rm = TRUE
    ),
    
    post_index_date_first_severe_retinopathy =
      if_else(post_index_date_first_severe_retinopathy == as.Date("2050-01-01"),
              as.Date(NA), post_index_date_first_severe_retinopathy),
    
    post_index_date_severe_retinopathy =
      as.integer(!is.na(post_index_date_first_severe_retinopathy))
  ) %>%
  # keep just retinopathy non-severe and severe columns 
  select(
    patid,
    
    # non-severe retinopathy
    pre_index_date_earliest_non_severe_retinopathy,
    pre_index_date_latest_non_severe_retinopathy,
    pre_index_date_non_severe_retinopathy,
    post_index_date_first_non_severe_retinopathy,
    post_index_date_non_severe_retinopathy,
    
    # severe retinopathy 
    pre_index_date_earliest_severe_retinopathy,
    pre_index_date_latest_severe_retinopathy,
    pre_index_date_severe_retinopathy,
    post_index_date_first_severe_retinopathy,
    post_index_date_severe_retinopathy,
    
    pre_index_date_vitreous_and_pre_retinal_haemorrhage,
    post_index_date_first_vitreous_and_pre_retinal_haemorrhage, 
    pre_index_date_proliferative_retinopathy,
    post_index_date_first_proliferative_retinopathy, 
    pre_index_date_blindness_and_visual_impairment,
    post_index_date_first_blindness_and_visual_impairment
  )


analysis <- cprd$analysis("at_diag")
retinopathy_severity <- retinopathy_severity %>%
  analysis$cached("retinopathy_severity_relaxed", unique_indexes="patid")


###############################################################################

# Neuropathy


# Join index dates with neuroapthy complications
neuropathy_severity <- index_dates %>%
  left_join(
    comorbidities %>%
      select(
        patid,
        index_date,
        
        # non-severe neuropathy
        pre_index_date_earliest_non_severe_neuropathy,
        pre_index_date_latest_non_severe_neuropathy,
        pre_index_date_non_severe_neuropathy,
        post_index_date_first_non_severe_neuropathy,
        
        # foot ulcer / infection / ischaemia 
        pre_index_date_earliest_foot_ulcer_infection_ischaemia,
        pre_index_date_foot_ulcer_infection_ischaemia,
        post_index_date_first_foot_ulcer_infection_ischaemia,

        # gastroparesis 
        pre_index_date_earliest_gastroparesis,
        pre_index_date_latest_gastroparesis,
        post_index_date_first_gastroparesis,

        # charcot foot
        pre_index_date_earliest_charcot_foot,
        pre_index_date_charcot_foot,
        post_index_date_first_charcot_foot,

        # painful peripheral neuropathy 
        pre_index_date_earliest_painful_peripheral_neuropathy,
        pre_index_date_painful_peripheral_neuropathy,
        post_index_date_first_painful_peripheral_neuropathy,

        # neuropathic pain 
        pre_index_date_earliest_neuropathic_pain,
        pre_index_date_neuropathic_pain,
        post_index_date_first_neuropathic_pain,

        # lower limb amputation 
        pre_index_date_earliest_lower_limb_amputation,
        pre_index_date_lower_limb_amputation,
        post_index_date_first_lower_limb_amputation
      ),
    by = c("patid", "index_date")
  )


# Create severe_neuropathy composite and create pre and post flags/dates
neuropathy_severity <- neuropathy_severity %>%
  mutate(
    ## --- Non-severe neuropathy ---
    
    # Post flag for non-severe neuropathy
    post_index_date_non_severe_neuropathy =
      as.integer(!is.na(post_index_date_first_non_severe_neuropathy)),
    
    
    ## --- Severe neuropathy (composite) ---
    #  - foot_ulcer_infection_ischaemia
    #  - charcot_foot
    #  - painful_peripheral_neuropathy
    #  - neuropathic_pain
    #  - lower_limb_amputation
    #  - gastroparesis 
    
    # PRE: earliest severe neuropathy
    pre_index_date_earliest_severe_neuropathy = pmin(
      if_else(!is.na(pre_index_date_earliest_foot_ulcer_infection_ischaemia),
              pre_index_date_earliest_foot_ulcer_infection_ischaemia,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_charcot_foot),
              pre_index_date_earliest_charcot_foot,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_painful_peripheral_neuropathy),
              pre_index_date_earliest_painful_peripheral_neuropathy,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_neuropathic_pain),
              pre_index_date_earliest_neuropathic_pain,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_lower_limb_amputation),
              pre_index_date_earliest_lower_limb_amputation,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_gastroparesis),
              pre_index_date_earliest_gastroparesis,
              as.Date("2050-01-01")),
      na.rm = TRUE
    ),
    
    # PRE: latest severe neuropathy
    pre_index_date_latest_severe_neuropathy = pmax(
      if_else(!is.na(pre_index_date_earliest_foot_ulcer_infection_ischaemia),
              pre_index_date_earliest_foot_ulcer_infection_ischaemia,
              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_earliest_charcot_foot),
              pre_index_date_earliest_charcot_foot,
              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_earliest_painful_peripheral_neuropathy),
              pre_index_date_earliest_painful_peripheral_neuropathy,
              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_earliest_neuropathic_pain),
              pre_index_date_earliest_neuropathic_pain,
              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_earliest_lower_limb_amputation),
              pre_index_date_earliest_lower_limb_amputation,
              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_latest_gastroparesis),
              pre_index_date_latest_gastroparesis,
              as.Date("1900-01-01")),
      na.rm = TRUE
    ),
    
    # Convert back to NA
    pre_index_date_earliest_severe_neuropathy =
      if_else(pre_index_date_earliest_severe_neuropathy == as.Date("2050-01-01"),
              as.Date(NA), pre_index_date_earliest_severe_neuropathy),
    
    pre_index_date_latest_severe_neuropathy =
      if_else(pre_index_date_latest_severe_neuropathy == as.Date("1900-01-01"),
              as.Date(NA), pre_index_date_latest_severe_neuropathy),
    
    # PRE flag
    pre_index_date_severe_neuropathy =
      as.integer(!is.na(pre_index_date_earliest_severe_neuropathy)),
    
    
    # POST: first severe neuropathy after diagnosis
    post_index_date_first_severe_neuropathy = pmin(
      if_else(!is.na(post_index_date_first_foot_ulcer_infection_ischaemia),
              post_index_date_first_foot_ulcer_infection_ischaemia,
              as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_charcot_foot),
              post_index_date_first_charcot_foot,
              as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_painful_peripheral_neuropathy),
              post_index_date_first_painful_peripheral_neuropathy,
              as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_neuropathic_pain),
              post_index_date_first_neuropathic_pain,
              as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_lower_limb_amputation),
              post_index_date_first_lower_limb_amputation,
              as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_gastroparesis),
              post_index_date_first_gastroparesis,
              as.Date("2050-01-01")),
      na.rm = TRUE
    ),
    
    post_index_date_first_severe_neuropathy =
      if_else(post_index_date_first_severe_neuropathy == as.Date("2050-01-01"),
              as.Date(NA), post_index_date_first_severe_neuropathy),
    
    post_index_date_severe_neuropathy =
      as.integer(!is.na(post_index_date_first_severe_neuropathy))
  ) %>%
  select(
    patid,
    
    # non-severe neuropathy
    pre_index_date_earliest_non_severe_neuropathy,
    pre_index_date_latest_non_severe_neuropathy,
    pre_index_date_non_severe_neuropathy,
    post_index_date_first_non_severe_neuropathy,
    post_index_date_non_severe_neuropathy,
    
    # severe neuropathy 
    pre_index_date_earliest_severe_neuropathy,
    pre_index_date_latest_severe_neuropathy,
    pre_index_date_severe_neuropathy,
    post_index_date_first_severe_neuropathy,
    post_index_date_severe_neuropathy, 
    
    # non-severe neuropathy
    pre_index_date_earliest_non_severe_neuropathy,
    pre_index_date_latest_non_severe_neuropathy,
    pre_index_date_non_severe_neuropathy,
    post_index_date_first_non_severe_neuropathy,
    
    # foot ulcer / infection / ischaemia 
    pre_index_date_foot_ulcer_infection_ischaemia,
    post_index_date_first_foot_ulcer_infection_ischaemia,
    
    # gastroparesis 
    pre_index_date_latest_gastroparesis,
    post_index_date_first_gastroparesis,
    
    # charcot foot
    pre_index_date_charcot_foot,
    post_index_date_first_charcot_foot,
    
    # painful peripheral neuropathy 
    pre_index_date_painful_peripheral_neuropathy,
    post_index_date_first_painful_peripheral_neuropathy,
    
    # neuropathic pain 
    pre_index_date_neuropathic_pain,
    post_index_date_first_neuropathic_pain,
    
    # lower limb amputation 
    pre_index_date_lower_limb_amputation,
    post_index_date_first_lower_limb_amputation
  )
    
  



analysis <- cprd$analysis("at_diag")
neuropathy_severity <- neuropathy_severity %>%
  analysis$cached("neuropathy_severity_relaxed", unique_indexes = "patid")



###############################################################################

# Nephropathy

# Kidney failure death primary cause
analysis <- cprd$analysis("all")
death_kf_primary <- death_kf_primary %>% analysis$cached("death_kf_primary")

# egfr40 decline, ACR_confirmed, and CKD stages
analysis <- cprd$analysis("at_diag")
baseline_biomarkers <- baseline_biomarkers %>% analysis$cached("baseline_biomarkers") 
ckd_stages <- ckd_stages %>% analysis$cached("ckd_stages")  


# Join ckd stages, ACR and eGFR variables with index dates
nephropathy_flags <- index_dates %>%
  left_join(ckd_stages, by = "patid") %>%
  left_join(
    baseline_biomarkers %>% 
      select(patid, index_date,
             # ACR confirmed 
             preacr_confirmed, preacr_confirmed_earliest, preacr_confirmed_latest,
             postacr_confirmed, postacr_confirmed_earliest,
             # 40% and 50% eGFR decline 
             postegfr_40_decline_confirmed, postegfr_40_decline_confirmed_earliest,
             postegfr_50_decline_confirmed, postegfr_50_decline_confirmed_earliest
      ),
    by = c("patid","index_date")
  ) %>%
  # Join kidney failure death primary cause and keep the death date from diabetes_cohort
  left_join(death_kf_primary %>% select(patid, kf_death_primary_cause), by = "patid") %>%
  left_join(diabetes_cohort %>% select(patid, death_date), by = "patid") %>%
  left_join(comorbidities %>% select(patid, pre_index_date_earliest_ckd5_code, pre_index_date_latest_ckd5_code,pre_index_date_ckd5_code, post_index_date_first_ckd5_code), by = "patid")


## --- Non severe nephropathy-----
non_severe_nephropathy <- nephropathy_flags %>%
  mutate(
    pre_ckd3a_date = if_else(preckdstage == "stage_3a", preckdstagedate, as.Date(NA)),
    
    # Pre non-severe = Pre ACR confirmed OR baseline stage_3a CKD
    pre_index_date_earliest_non_severe_nephropathy = pmin(
      if_else(preacr_confirmed == 1L & !is.na(preacr_confirmed_earliest),
              preacr_confirmed_earliest, as.Date("2050-01-01")),
      if_else(!is.na(pre_ckd3a_date),
              pre_ckd3a_date,            as.Date("2050-01-01")),
      na.rm = TRUE
    ),
    pre_index_date_latest_non_severe_nephropathy = pmax(
      if_else(preacr_confirmed == 1L & !is.na(preacr_confirmed_latest),
              preacr_confirmed_latest, as.Date("1900-01-01")),
      if_else(!is.na(pre_ckd3a_date),
              pre_ckd3a_date,          as.Date("1900-01-01")),
      na.rm = TRUE
    ),
    
    pre_index_date_earliest_non_severe_nephropathy =
      if_else(pre_index_date_earliest_non_severe_nephropathy == as.Date("2050-01-01"),
              as.Date(NA), pre_index_date_earliest_non_severe_nephropathy),
    pre_index_date_latest_non_severe_nephropathy =
      if_else(pre_index_date_latest_non_severe_nephropathy   == as.Date("1900-01-01"),
              as.Date(NA), pre_index_date_latest_non_severe_nephropathy),
    
    # Pre flag
    pre_index_date_non_severe_nephropathy =
      as.integer(!is.na(pre_index_date_earliest_non_severe_nephropathy)),
    
    # Post non-severe = Post ACR-confirmed OR post stage_3a
    post_index_date_first_non_severe_nephropathy = pmin(
      if_else(postacr_confirmed == 1L & !is.na(postacr_confirmed_earliest),
              postacr_confirmed_earliest, as.Date("2050-01-01")),
      if_else(!is.na(postckdstage3a_date),
              postckdstage3a_date,       as.Date("2050-01-01")),
      na.rm = TRUE
    ),
    post_index_date_first_non_severe_nephropathy =
      if_else(post_index_date_first_non_severe_nephropathy == as.Date("2050-01-01"),
              as.Date(NA), post_index_date_first_non_severe_nephropathy),
    
    post_index_date_non_severe_nephropathy =
      as.integer(!is.na(post_index_date_first_non_severe_nephropathy))
  ) %>% 
  select(
    patid,
    pre_index_date_earliest_non_severe_nephropathy,
    pre_index_date_latest_non_severe_nephropathy,
    pre_index_date_non_severe_nephropathy,
    post_index_date_first_non_severe_nephropathy,
    post_index_date_non_severe_nephropathy
  )




## --- Severe nephropathy-----
severe_nephropathy <- nephropathy_flags %>%
  mutate(
    # Pre severe: CKD stage 5 (stage_5 or CKD5 code pre-index)
    pre_index_date_earliest_severe_nephropathy = pmin(
      if_else(preckdstage == "stage_5" & !is.na(preckdstagedate),
              preckdstagedate,              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_ckd5_code),
              pre_index_date_earliest_ckd5_code, as.Date("2050-01-01")),
      na.rm = TRUE
    ),
    pre_index_date_latest_severe_nephropathy = pmax(
      if_else(preckdstage == "stage_5" & !is.na(preckdstagedate),
              preckdstagedate,              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_latest_ckd5_code),
              pre_index_date_latest_ckd5_code,   as.Date("1900-01-01")),
      na.rm = TRUE
    ),
    
    pre_index_date_earliest_severe_nephropathy =
      if_else(pre_index_date_earliest_severe_nephropathy == as.Date("2050-01-01"),
              as.Date(NA), pre_index_date_earliest_severe_nephropathy),
    pre_index_date_latest_severe_nephropathy =
      if_else(pre_index_date_latest_severe_nephropathy   == as.Date("1900-01-01"),
              as.Date(NA), pre_index_date_latest_severe_nephropathy),
    
    # Pre flag
    pre_index_date_severe_nephropathy =
      as.integer(!is.na(pre_index_date_earliest_severe_nephropathy)),
    
    # Post severe: CKD stage 5 OR 40% decline in eGFR (confirmed) OR KF death
    post_kf_death_date = if_else(
      kf_death_primary_cause == 1L & death_date > index_date,
      death_date, as.Date(NA)
    ),
    
    post_index_date_first_severe_nephropathy = pmin(
      if_else(!is.na(postckdstage5_date),
              postckdstage5_date,                  as.Date("2050-01-01")),
      if_else(!is.na(postegfr_40_decline_confirmed_earliest),
              postegfr_40_decline_confirmed_earliest, as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_ckd5_code),
              post_index_date_first_ckd5_code,     as.Date("2050-01-01")),
      if_else(!is.na(post_kf_death_date),
              post_kf_death_date,                  as.Date("2050-01-01")),
      na.rm = TRUE
    ),
    post_index_date_first_severe_nephropathy =
      if_else(post_index_date_first_severe_nephropathy == as.Date("2050-01-01"),
              as.Date(NA), post_index_date_first_severe_nephropathy),
    
    # post flag
    post_index_date_severe_nephropathy =
      as.integer(!is.na(post_index_date_first_severe_nephropathy))
  ) %>% 
  select(
    patid,
    pre_index_date_earliest_severe_nephropathy,
    pre_index_date_latest_severe_nephropathy,
    pre_index_date_severe_nephropathy,
    post_index_date_first_severe_nephropathy,
    post_index_date_severe_nephropathy
  )



analysis <- cprd$analysis("at_diag")

nephropathy_severity <- non_severe_nephropathy %>%
  left_join(severe_nephropathy, by = "patid") %>%
  analysis$cached("nephropathy_severity", unique_indexes="patid")

###############################################################################

# Join retinopathy, neuroapthy and nephropathy and create variable of "any" microvascular
# complication with pre and post date 
microvascular_complications <- index_dates %>%
  left_join(retinopathy_severity, by = "patid") %>%
  left_join(neuropathy_severity,  by = "patid") %>%
  left_join(nephropathy_severity, by = "patid") %>%
  # ---------------- ANY non-severe microvascular (pre & post) ----------------
mutate(
  pre_index_date_earliest_non_severe_microvasc_any = pmin(
    coalesce(pre_index_date_earliest_non_severe_nephropathy, as.Date("2050-01-01")),
    coalesce(pre_index_date_earliest_non_severe_neuropathy,  as.Date("2050-01-01")),
    coalesce(pre_index_date_earliest_non_severe_retinopathy, as.Date("2050-01-01")),
    na.rm = TRUE
  ),
  pre_index_date_latest_non_severe_microvasc_any = pmax(
    coalesce(pre_index_date_latest_non_severe_nephropathy, as.Date("1900-01-01")),
    coalesce(pre_index_date_latest_non_severe_neuropathy,  as.Date("1900-01-01")),
    coalesce(pre_index_date_latest_non_severe_retinopathy,  as.Date("1900-01-01")),
    na.rm = TRUE
  ),
  pre_index_date_earliest_non_severe_microvasc_any =
    if_else(pre_index_date_earliest_non_severe_microvasc_any == as.Date("2050-01-01"), as.Date(NA), pre_index_date_earliest_non_severe_microvasc_any),
  pre_index_date_latest_non_severe_microvasc_any =
    if_else(pre_index_date_latest_non_severe_microvasc_any   == as.Date("1900-01-01"), as.Date(NA), pre_index_date_latest_non_severe_microvasc_any),
  pre_index_date_non_severe_microvasc_any = as.integer(!is.na(pre_index_date_earliest_non_severe_microvasc_any)),
  
  post_index_date_first_non_severe_microvasc_any = pmin(
    coalesce(post_index_date_first_non_severe_nephropathy, as.Date("2050-01-01")),
    coalesce(post_index_date_first_non_severe_neuropathy,  as.Date("2050-01-01")),
    coalesce(post_index_date_first_non_severe_retinopathy, as.Date("2050-01-01")),
    na.rm = TRUE
  ),
  post_index_date_first_non_severe_microvasc_any =
    if_else(post_index_date_first_non_severe_microvasc_any == as.Date("2050-01-01"), as.Date(NA), post_index_date_first_non_severe_microvasc_any),
  post_index_date_non_severe_microvasc_any = as.integer(!is.na(post_index_date_first_non_severe_microvasc_any)),
  
  # ---------------- ANY severe microvascular (pre & post) ----------------
  pre_index_date_earliest_severe_microvasc_any = pmin(
    coalesce(pre_index_date_earliest_severe_nephropathy, as.Date("2050-01-01")),
    coalesce(pre_index_date_earliest_severe_neuropathy,  as.Date("2050-01-01")),
    coalesce(pre_index_date_earliest_severe_retinopathy, as.Date("2050-01-01")),
    na.rm = TRUE
  ),
  pre_index_date_latest_severe_microvasc_any = pmax(
    coalesce(pre_index_date_latest_severe_nephropathy, as.Date("1900-01-01")),
    coalesce(pre_index_date_latest_severe_neuropathy,  as.Date("1900-01-01")),
    coalesce(pre_index_date_latest_severe_retinopathy,  as.Date("1900-01-01")),
    na.rm = TRUE
  ),
  pre_index_date_earliest_severe_microvasc_any =
    if_else(pre_index_date_earliest_severe_microvasc_any == as.Date("2050-01-01"), as.Date(NA), pre_index_date_earliest_severe_microvasc_any),
  pre_index_date_latest_severe_microvasc_any =
    if_else(pre_index_date_latest_severe_microvasc_any   == as.Date("1900-01-01"), as.Date(NA), pre_index_date_latest_severe_microvasc_any),
  pre_index_date_severe_microvasc_any = as.integer(!is.na(pre_index_date_earliest_severe_microvasc_any)),
  
  post_index_date_first_severe_microvasc_any = pmin(
    coalesce(post_index_date_first_severe_nephropathy, as.Date("2050-01-01")),
    coalesce(post_index_date_first_severe_neuropathy,  as.Date("2050-01-01")),
    coalesce(post_index_date_first_severe_retinopathy, as.Date("2050-01-01")),
    na.rm = TRUE
  ),
  post_index_date_first_severe_microvasc_any =
    if_else(post_index_date_first_severe_microvasc_any == as.Date("2050-01-01"), as.Date(NA), post_index_date_first_severe_microvasc_any),
  post_index_date_severe_microvasc_any = as.integer(!is.na(post_index_date_first_severe_microvasc_any))
)



microvascular_complications <- microvascular_complications %>%
  analysis$cached("microvascular_complications_relaxed", unique_indexes = "patid")





###############################################################################
# UKPDS composite 
###############################################################################

# Severe diabetes-related complications (compostie outcome) defined according to recent UK Prospective Diabetes Study # (UKPDS) criteria: sudden death; death due to hyperglycaemia or hypoglycaemia; fatal or non-fatal myocardial 
# infarction, angina, heart failure, stroke, or kidney failure; death from peripheral vascular disease; amputation;
# and severe retinopathy (vitreous haemorrhage or retinal photocoagulation). Events were identified using HES and 
# death registry data (primary cause only), with additional capture of kidney failure from primary care codes. 



analysis <- cprd$analysis("all")
death_causes <- death_causes %>% analysis$cached("death_causes")

ukpds <- index_dates %>%
  left_join(diabetes_cohort %>% select(patid, death_date), by = "patid") %>%
  left_join(
    death_causes %>% select(
      patid,
      cv_death_primary_cause,
      pvd_death_primary_cause,
      sudden_death_primary_cause,
      hyperglycaemia_death_primary_cause,
      hypoglycaemia_death_primary_cause,
      hf_death_primary_cause,
      kf_death_primary_cause
    ),
    by = "patid"
  ) %>%
  left_join(
    comorbidities %>% select(
      patid, index_date,
      
      # UKPDS cardiovascular events
      pre_index_date_earliest_primary_incident_mi,
      pre_index_date_latest_primary_incident_mi,
      post_index_date_first_primary_incident_mi,
      
      pre_index_date_earliest_primary_hhf,
      pre_index_date_latest_primary_hhf,
      post_index_date_first_primary_hhf,
      
      pre_index_date_earliest_primary_incident_stroke,
      pre_index_date_latest_primary_incident_stroke,
      post_index_date_first_primary_incident_stroke,
      
      # Renal
      pre_index_date_earliest_ckd5_code,
      pre_index_date_latest_ckd5_code,
      post_index_date_first_ckd5_code,
      
      # Amputation
      pre_index_date_earliest_amputation,
      pre_index_date_latest_amputation,
      post_index_date_first_amputation,
      
      # Eye (UKPDS-specific)
      pre_index_date_earliest_vitreoushemorrhage,
      pre_index_date_latest_vitreoushemorrhage,
      post_index_date_first_vitreoushemorrhage,
      
      pre_index_date_earliest_ukpds_photocoagulation,
      pre_index_date_latest_ukpds_photocoagulation,
      post_index_date_first_ukpds_photocoagulation
    ),
    by = c("patid", "index_date")
  ) %>%
  mutate(
    # ---------------- post-index primary-cause death dates ----------------
    post_cv_death_primary_cause_date =
      if_else(cv_death_primary_cause == 1L & death_date > index_date, death_date, as.Date(NA)),
    post_pvd_death_primary_cause_date =
      if_else(pvd_death_primary_cause == 1L & death_date > index_date, death_date, as.Date(NA)),
    post_sudden_death_primary_cause_date =
      if_else(sudden_death_primary_cause == 1L & death_date > index_date, death_date, as.Date(NA)),
    post_hyperglycaemia_death_primary_cause_date =
      if_else(hyperglycaemia_death_primary_cause == 1L & death_date > index_date, death_date, as.Date(NA)),
    post_hypoglycaemia_death_primary_cause_date =
      if_else(hypoglycaemia_death_primary_cause == 1L & death_date > index_date, death_date, as.Date(NA)),
    post_hf_death_primary_cause_date =
      if_else(hf_death_primary_cause == 1L & death_date > index_date, death_date, as.Date(NA)),
    post_kf_death_primary_cause_date =
      if_else(kf_death_primary_cause == 1L & death_date > index_date, death_date, as.Date(NA)),
    
    # ---------------- PRE UKPDS ----------------
    pre_index_date_earliest_ukpds = pmin(
      coalesce(pre_index_date_earliest_primary_incident_mi, as.Date("2050-01-01")),
      coalesce(pre_index_date_earliest_primary_hhf,         as.Date("2050-01-01")),
      coalesce(pre_index_date_earliest_primary_incident_stroke, as.Date("2050-01-01")),
      coalesce(pre_index_date_earliest_ckd5_code,            as.Date("2050-01-01")),
      coalesce(pre_index_date_earliest_amputation,           as.Date("2050-01-01")),
      coalesce(pre_index_date_earliest_vitreoushemorrhage,   as.Date("2050-01-01")),
      coalesce(pre_index_date_earliest_ukpds_photocoagulation, as.Date("2050-01-01")),
      na.rm = TRUE
    ),
    
    pre_index_date_latest_ukpds = pmax(
      coalesce(pre_index_date_latest_primary_incident_mi, as.Date("1900-01-01")),
      coalesce(pre_index_date_latest_primary_hhf,         as.Date("1900-01-01")),
      coalesce(pre_index_date_latest_primary_incident_stroke, as.Date("1900-01-01")),
      coalesce(pre_index_date_latest_ckd5_code,            as.Date("1900-01-01")),
      coalesce(pre_index_date_latest_amputation,           as.Date("1900-01-01")),
      coalesce(pre_index_date_latest_vitreoushemorrhage,   as.Date("1900-01-01")),
      coalesce(pre_index_date_latest_ukpds_photocoagulation, as.Date("1900-01-01")),
      na.rm = TRUE
    ),
    
    pre_index_date_earliest_ukpds =
      if_else(pre_index_date_earliest_ukpds == as.Date("2050-01-01"),
              as.Date(NA), pre_index_date_earliest_ukpds),
    pre_index_date_latest_ukpds =
      if_else(pre_index_date_latest_ukpds == as.Date("1900-01-01"),
              as.Date(NA), pre_index_date_latest_ukpds),
    
    pre_index_date_ukpds = as.integer(!is.na(pre_index_date_earliest_ukpds)),
    
    # ---------------- POST UKPDS ----------------
    post_index_date_first_ukpds = pmin(
      coalesce(post_index_date_first_primary_incident_mi, as.Date("2050-01-01")),
      coalesce(post_index_date_first_primary_hhf,         as.Date("2050-01-01")),
      coalesce(post_index_date_first_primary_incident_stroke, as.Date("2050-01-01")),
      coalesce(post_index_date_first_ckd5_code,            as.Date("2050-01-01")),
      coalesce(post_index_date_first_amputation,           as.Date("2050-01-01")),
      coalesce(post_index_date_first_vitreoushemorrhage,   as.Date("2050-01-01")),
      coalesce(post_index_date_first_ukpds_photocoagulation, as.Date("2050-01-01")),
      coalesce(post_cv_death_primary_cause_date,            as.Date("2050-01-01")),
      coalesce(post_pvd_death_primary_cause_date,           as.Date("2050-01-01")),
      coalesce(post_sudden_death_primary_cause_date,        as.Date("2050-01-01")),
      coalesce(post_hyperglycaemia_death_primary_cause_date,as.Date("2050-01-01")),
      coalesce(post_hypoglycaemia_death_primary_cause_date, as.Date("2050-01-01")),
      coalesce(post_hf_death_primary_cause_date,            as.Date("2050-01-01")),
      coalesce(post_kf_death_primary_cause_date,            as.Date("2050-01-01")),
      na.rm = TRUE
    ),
    
    post_index_date_first_ukpds =
      if_else(post_index_date_first_ukpds == as.Date("2050-01-01"),
              as.Date(NA), post_index_date_first_ukpds),
    
    post_index_date_ukpds = as.integer(!is.na(post_index_date_first_ukpds))
  ) %>%
  select(
    patid,
    pre_index_date_earliest_ukpds,
    pre_index_date_latest_ukpds,
    pre_index_date_ukpds,
    post_index_date_first_ukpds,
    post_index_date_ukpds
  )



analysis <- cprd$analysis("at_diag")
ukpds <- ukpds %>%
  analysis$cached("ukpds", unique_indexes = "patid")
