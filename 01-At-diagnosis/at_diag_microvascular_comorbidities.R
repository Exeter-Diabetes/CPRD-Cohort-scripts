

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

# These severe complications are only classified as diabetes-related 
# when a non-severe microvascular code is present before. 
# This avoids misclassifying non-diabetic causes (e.g., amputation from accident, 
# non-diabetic blindness) as diabetic microvascular outcomes.
starred <- tibble::tribble(
  ~severe,                             ~family,
  "blindness_and_visual_impairment",   "retinopathy",
  "foot_ulcer_infection_ischaemia",    "neuropathy",
  "charcot_foot",                      "neuropathy",
  "painful_peripheral_neuropathy",     "neuropathy",
  "neuropathic_pain",                  "neuropathy",
  "lower_limb_amputation",             "neuropathy"
)


for (i in seq_len(nrow(starred))) {
  
  sev <- starred$severe[i]
  fam <- starred$family[i]
  
  # Existing columns
  pre_sev_col   <- paste0("pre_index_date_earliest_", sev)
  post_sev_col  <- paste0("post_index_date_first_", sev)
  
  pre_ns_col    <- paste0("pre_index_date_earliest_non_severe_", fam)
  post_ns_col   <- paste0("post_index_date_first_non_severe_", fam)
  
  # New columns 
  pre_star_date <- paste0("pre_index_date_earliest_", sev, "_with_non_severe")
  pre_star_flag <- paste0("pre_index_date_", sev, "_with_non_severe")
  
  post_star_date <- paste0("post_index_date_first_", sev, "_with_non_severe")
  post_star_flag <- paste0("post_index_date_", sev, "_with_non_severe")
  
  comorbidities <- comorbidities %>%
    mutate(
      # PRE: severe only if pre non-severe exists and is <= pre severe date
      !!pre_star_date := case_when(
        !is.na(.data[[pre_sev_col]]) &
          !is.na(.data[[pre_ns_col]]) &
          .data[[pre_ns_col]] <= .data[[pre_sev_col]] ~ .data[[pre_sev_col]],
        TRUE ~ as.Date(NA)
      ),
      !!pre_star_flag := as.integer(!is.na(.data[[pre_star_date]])),
      
      # POST: severe only if any non-severe (pre or post) exists
      #       and occurs on/before the post severe date
      !!post_star_date := case_when(
        !is.na(.data[[post_sev_col]]) &
          !is.na(coalesce(.data[[pre_ns_col]], .data[[post_ns_col]])) &
          coalesce(.data[[pre_ns_col]], .data[[post_ns_col]]) <= .data[[post_sev_col]] ~
          .data[[post_sev_col]],
        TRUE ~ as.Date(NA)
      ),
      !!post_star_flag := as.integer(!is.na(.data[[post_star_date]]))
    )
}

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
      "pre_index_date_earliest_blindness_and_visual_impairment_with_non_severe",
      "pre_index_date_blindness_and_visual_impairment_with_non_severe",
      "post_index_date_first_blindness_and_visual_impairment_with_non_severe",
      "post_index_date_blindness_and_visual_impairment_with_non_severe"
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
    #  - blindness_and_visual_impairment_with_non_severe (only those with prior non-severe)
    
    # PRE: earliest severe retinopathy
    pre_index_date_earliest_severe_retinopathy = pmin(
      if_else(!is.na(pre_index_date_earliest_vitreous_and_pre_retinal_haemorrhage),
              pre_index_date_earliest_vitreous_and_pre_retinal_haemorrhage,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_proliferative_retinopathy),
              pre_index_date_earliest_proliferative_retinopathy,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_blindness_and_visual_impairment_with_non_severe),
              pre_index_date_earliest_blindness_and_visual_impairment_with_non_severe,
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
      if_else(!is.na(pre_index_date_earliest_blindness_and_visual_impairment_with_non_severe),
              pre_index_date_earliest_blindness_and_visual_impairment_with_non_severe,
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
      if_else(!is.na(post_index_date_first_blindness_and_visual_impairment_with_non_severe),
              post_index_date_first_blindness_and_visual_impairment_with_non_severe,
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
    post_index_date_severe_retinopathy
  )

retinopathy_severity

analysis <- cprd$analysis("at_diag")
retinopathy_severity <- retinopathy_severity %>%
  analysis$cached("retinopathy_severity", unique_indexes="patid")

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
        pre_index_date_earliest_foot_ulcer_infection_ischaemia_with_non_severe,
        pre_index_date_foot_ulcer_infection_ischaemia_with_non_severe,
        post_index_date_first_foot_ulcer_infection_ischaemia_with_non_severe,
        post_index_date_foot_ulcer_infection_ischaemia_with_non_severe,
        
        # gastroparesis 
        pre_index_date_earliest_gastroparesis,
        pre_index_date_latest_gastroparesis,
        pre_index_date_gastroparesis,
        post_index_date_first_gastroparesis,
        
        # charcot foot
        pre_index_date_earliest_charcot_foot_with_non_severe,
        pre_index_date_charcot_foot_with_non_severe,
        post_index_date_first_charcot_foot_with_non_severe,
        post_index_date_charcot_foot_with_non_severe,
        
        # painful peripheral neuropathy 
        pre_index_date_earliest_painful_peripheral_neuropathy_with_non_severe,
        pre_index_date_painful_peripheral_neuropathy_with_non_severe,
        post_index_date_first_painful_peripheral_neuropathy_with_non_severe,
        post_index_date_painful_peripheral_neuropathy_with_non_severe,
        
        # neuropathic pain 
        pre_index_date_earliest_neuropathic_pain_with_non_severe,
        pre_index_date_neuropathic_pain_with_non_severe,
        post_index_date_first_neuropathic_pain_with_non_severe,
        post_index_date_neuropathic_pain_with_non_severe,
        
        # lower limb amputation 
        pre_index_date_earliest_lower_limb_amputation_with_non_severe,
        pre_index_date_lower_limb_amputation_with_non_severe,
        post_index_date_first_lower_limb_amputation_with_non_severe,
        post_index_date_lower_limb_amputation_with_non_severe
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
    #  - foot_ulcer_infection_ischaemia_with_non_severe
    #  - charcot_foot_with_non_severe
    #  - painful_peripheral_neuropathy_with_non_severe
    #  - neuropathic_pain_with_non_severe
    #  - lower_limb_amputation_with_non_severe
    #  - gastroparesis 
    
    # PRE: earliest severe neuropathy
    pre_index_date_earliest_severe_neuropathy = pmin(
      if_else(!is.na(pre_index_date_earliest_foot_ulcer_infection_ischaemia_with_non_severe),
              pre_index_date_earliest_foot_ulcer_infection_ischaemia_with_non_severe,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_charcot_foot_with_non_severe),
              pre_index_date_earliest_charcot_foot_with_non_severe,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_painful_peripheral_neuropathy_with_non_severe),
              pre_index_date_earliest_painful_peripheral_neuropathy_with_non_severe,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_neuropathic_pain_with_non_severe),
              pre_index_date_earliest_neuropathic_pain_with_non_severe,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_lower_limb_amputation_with_non_severe),
              pre_index_date_earliest_lower_limb_amputation_with_non_severe,
              as.Date("2050-01-01")),
      if_else(!is.na(pre_index_date_earliest_gastroparesis),
              pre_index_date_earliest_gastroparesis,
              as.Date("2050-01-01")),
      na.rm = TRUE
    ),
    
    # PRE: latest severe neuropathy
    pre_index_date_latest_severe_neuropathy = pmax(
      if_else(!is.na(pre_index_date_earliest_foot_ulcer_infection_ischaemia_with_non_severe),
              pre_index_date_earliest_foot_ulcer_infection_ischaemia_with_non_severe,
              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_earliest_charcot_foot_with_non_severe),
              pre_index_date_earliest_charcot_foot_with_non_severe,
              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_earliest_painful_peripheral_neuropathy_with_non_severe),
              pre_index_date_earliest_painful_peripheral_neuropathy_with_non_severe,
              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_earliest_neuropathic_pain_with_non_severe),
              pre_index_date_earliest_neuropathic_pain_with_non_severe,
              as.Date("1900-01-01")),
      if_else(!is.na(pre_index_date_earliest_lower_limb_amputation_with_non_severe),
              pre_index_date_earliest_lower_limb_amputation_with_non_severe,
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
      if_else(!is.na(post_index_date_first_foot_ulcer_infection_ischaemia_with_non_severe),
              post_index_date_first_foot_ulcer_infection_ischaemia_with_non_severe,
              as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_charcot_foot_with_non_severe),
              post_index_date_first_charcot_foot_with_non_severe,
              as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_painful_peripheral_neuropathy_with_non_severe),
              post_index_date_first_painful_peripheral_neuropathy_with_non_severe,
              as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_neuropathic_pain_with_non_severe),
              post_index_date_first_neuropathic_pain_with_non_severe,
              as.Date("2050-01-01")),
      if_else(!is.na(post_index_date_first_lower_limb_amputation_with_non_severe),
              post_index_date_first_lower_limb_amputation_with_non_severe,
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
    post_index_date_severe_neuropathy
  )




analysis <- cprd$analysis("at_diag")
neuropathy_severity <- neuropathy_severity %>%
  analysis$cached("neuropathy_severity", unique_indexes = "patid")


    


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

colnames(microvascular_complications)

# Join the new variables created (those requiring a non-severe code before)
# Rename "*_non_severe" to "*_ns" because mysql doesnt like length > 64 char
microvasc_starred <- comorbidities %>%
  select(patid, index_date, dplyr::contains("_with_non_severe")) %>%
  rename_with(~ str_replace(.x, "_with_non_severe$", "_ns"),
              ends_with("_with_non_severe"))


microvascular_complications <- microvascular_complications %>%
  left_join(select(microvasc_starred, -index_date), by = "patid") %>%
  analysis$cached("microvascular_complications", unique_indexes = "patid")


