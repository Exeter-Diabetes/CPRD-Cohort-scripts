
# Adds adherence for all drug class initated


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("mm")




############################################################################################

# Bring together drug class start dates (from drug_start_stop) and code max prescription dates
drug_class_start_stop <- drug_class_start_stop %>% analysis$cached("drug_class_start_stop")

# Load all prescribing records
all_scripts_long <- all_scripts_long %>% analysis$cached("all_scripts_long")

# Only take relevant scripts from dstartdate_class up to 15 months
adherence_relevant_scripts <- drug_class_start_stop %>%
  # Select important variables
  select(patid, drug_class, dstartdate_class, dstopdate_class) %>%

  # Compute the 15-month post-initiation cut-off -> this is to allow HbA1c12mresp dates
  mutate(post_index_15m = sql("date_add(dstartdate_class, interval 457 day)")) %>%
  
  # Join with prescription data
  left_join(
    all_scripts_long,
    by = c("patid", "drug_class")
  ) %>%
  
  # Restrict to prescriptions written during the adherence window
  filter(date >= dstartdate_class & date <= post_index_15m) %>%
  
  # Add dose metadata from CPRD
  left_join(
    cprd$tables$commonDose,
    by = c("dosageid")
  ) %>%
  
  # Cache
  analysis$cached("adherence_relevant_scripts", indexes = c("patid", "drug_class", "dstartdate_class"))
  

############################################################################################

# Calculate duration rules:

## Cleaning duration values using explicit rules:
# Rule 1: duration ≤ 0 → invalid → set to NA
# Rule 2: if duration missing but both quantity and daily_dose valid -> infer duration
# Rule 3: if duration missing but both quantiy and daily_dose valid (dose_unit == NA) -> infer duration
# Final: duration_cleaned = best available estimate following rules 1–2
adherence_relevant_scripts_duration <- adherence_relevant_scripts %>%
  
  # Rule 1: enforce removal of invalid durations
  mutate(duration_rule_1 = ifelse(!is.na(duration) & duration <= 0, NA, duration)) %>%
  
  # Cache
  analysis$cached("adherence_relevant_scripts_duration_interim_1", indexes = c("patid", "drug_class", "dstartdate_class")) %>%
  
  # Rule 2: infer duration if possible using quantity / daily_dose
  mutate(duration_rule_2 = ifelse(
    is.na(duration_rule_1) &
      !is.na(daily_dose) & daily_dose > 0 &
      !is.na(quantity) & quantity > 0,
    quantity / daily_dose,
    duration_rule_1
  )) %>%
  
  # Cache
  analysis$cached("adherence_relevant_scripts_duration_interim_2", indexes = c("patid", "drug_class", "dstartdate_class")) %>%
  
  # Rule 3: infer duration if possible using quantity / daily_dose (dose_unit == NA)
  mutate(duration_rule_3 = ifelse(
    is.na(duration_rule_1) &
      !is.na(daily_dose) & daily_dose > 0 & is.na(dose_unit) &
      !is.na(quantity) & quantity > 0,
    quantity / daily_dose,
    duration_rule_1
  )) %>%
  
  # Cache
  analysis$cached("adherence_relevant_scripts_duration_interim_3", indexes = c("patid", "drug_class", "dstartdate_class"))
  



############################################################################################

# Calculate start/stop dates: Bring together drug class start/stop dates (from drug_start_stop) and HbA1c response dates

## Load cached drug class start/stop tables
combo_class_start_stop <- combo_class_start_stop %>% analysis$cached("combo_class_start_stop")

## Load HbA1c outcome datasets (post-initiation)
post12m_hba1c <- post12m_hba1c %>% analysis$cached("post12m_hba1c")
post6m_hba1c <- post6m_hba1c %>% analysis$cached("post6m_hba1c")

# Adherence measures:
# - Start: dstartdate_class
#
# - Stop:
#  - Adherence for 12m post initiation, earliest of (NAME: _12m)
#    - 1y post initiation
#    - dstopdrug_class
#  - Adherence connected to HbA1c, earliest of (NAME: _combo_resp)
#    - 12m HbA1c outcome
#    - 6m HbA1c outcome
#    - dcstopdate (stop of drug combo)
#    - 1y post initiation

adherence_start_stop <- drug_class_start_stop %>%
  # Retain identifiers and therapy window boundaries
  select(patid, drug_class, dstartdate_class, dstopdate_class) %>%
  
  # Compute the 1-year post-initiation cut-off for truncating adherence periods
  mutate(one_year_post_initiation = sql("date_add(dstartdate_class, interval 365 day)")) %>%
  
  # Attach 12-month HbA1c response if available
  left_join(
    post12m_hba1c %>%
      rename(dstartdate_class = dstartdate) %>%   # Ensures exact match to therapy start date
      select(patid, drug_class, drug_substance, dstartdate_class, post_biomarker_12mdate),
    by = c("patid", "drug_class", "dstartdate_class")
  ) %>%
  
  # Attach 6-month HbA1c response if 12-month is missing
  left_join(
    post6m_hba1c %>%
      rename(dstartdate_class = dstartdate) %>%   # Same rationale as above
      select(patid, drug_class, dstartdate_class, post_biomarker_6mdate),
    by = c("patid", "drug_class", "dstartdate_class")
  ) %>%
  
  # Attach drug combo nextremdrug
  left_join(
    combo_class_start_stop %>%
      select(patid, dcstartdate, dcstopdate),
    by = c("patid", "dstartdate_class" = "dcstartdate")
  ) %>%
  
  # Determine the adherence start and stop dates for both variables
  mutate(
    ## Stop for adherence 12m
    max_adherence_date_12m = pmin(dstopdate_class, one_year_post_initiation, na.rm = TRUE),
    
    ## Stop for adherence connected to combo response
    max_adherence_date_combo_resp = case_when(
      # Primary: if a 12-month outcome exists, adherence window finishes there
      !is.na(post_biomarker_12mdate) ~ post_biomarker_12mdate,
      
      # Secondary: if a 6-month outcome exists, adherence window finishes there
      !is.na(post_biomarker_6mdate) ~ post_biomarker_6mdate,
      
      # Otherwise: end at earliest of drug combo stop or 1y cut-off
      TRUE ~ pmin(dcstopdate, one_year_post_initiation, na.rm = TRUE)
      
    )
  ) %>%
  
  # Keep only what is needed for adherence evaluation
  select(patid, drug_class, dstartdate_class, max_adherence_date_12m, max_adherence_date_combo_resp) %>%
  analysis$cached("adherence_start_stop", indexes = c("patid", "drug_class", "dstartdate_class"))




############################################################################################

# Calculate MPR based on different definitions:
#  - Max adherence date
#  - Prescription duration rules

## This caches a lot of tables with the names compute_mpr_int{1,2,3}{_suffix}


## Function computing MPR
compute_mpr <- function(duration_col, suffix, max_date_var) {
  
  # Input definitions
  ## duration_col: column containing the duration of the prescription 
  ## suffix: suffix for cached table and MPR variable - specification of the combo being tested
  ## max_date_var: column containing the max date of prescriptions
  
  # Link prescriptions in window (using placeholder names from input)
  interim_1 <- adherence_start_stop %>%
    ## Combine prescriptions
    inner_join(
      adherence_relevant_scripts_duration,
        by = c("patid", "drug_class", "dstartdate_class")
    ) %>%
    ## Select important variables
    select(
      patid, drug_class, dstartdate_class, !!sym(max_date_var), 
      date, coverage = !!sym(duration_col)
    ) %>%
    ## Select only important prescriptions
    filter(date >= dstartdate_class & date < !!sym(max_date_var)) %>%
    ## Cached
    analysis$cached(
      paste0("compute_mpr_int1_", suffix),
      indexes = c("patid", "drug_class", "dstartdate_class")
    )
  
  # Sum up coverage
  interim_2 <- interim_1 %>%
    ## Group by patid / drug taken / date of drug start
    group_by(patid, drug_class, dstartdate_class) %>%
    ## Calculate days covered by prescriptions in that period
    mutate(days_covered = sum(coverage, na.rm = TRUE)) %>%
    ## Remove grouping
    ungroup() %>%
    ## Select only important variables
    select(patid, drug_class, dstartdate_class, !!sym(max_date_var), days_covered) %>%
    ## Remove repeated rows from several prescriptions
    distinct() %>%
    ## Cached
    analysis$cached(
      paste0("compute_mpr_int2_", suffix),
      indexes = c("patid", "drug_class", "dstartdate_class")
    )
  
  # Compute MPR
  mpr <- interim_2 %>%
    ## Calculate days passed from drug start and max adherence date
    mutate(days_passed = datediff(!!sym(max_date_var), dstartdate_class)) %>%
    ## Calculate MPR (custom name for the function)
    mutate(!!paste0("MPR_", suffix) := days_covered / days_passed * 100) %>%
    ## Cached
    analysis$cached(
      paste0("compute_mpr_int3_", suffix),
      indexes = c("patid", "drug_class", "dstartdate_class")
    )
  
  return(mpr)
  
}


## Different adherence rules and durations

### Adherence 12m

mpr_12m_rule_1 <- compute_mpr(
  duration_col = "duration_rule_1",
  suffix = "12m_rule_1",
  max_date_var = "max_adherence_date_12m"
)

mpr_12m_rule_2 <- compute_mpr(
  duration_col = "duration_rule_2",
  suffix = "12m_rule_2",
  max_date_var = "max_adherence_date_12m"
)

mpr_12m_rule_3 <- compute_mpr(
  duration_col = "duration_rule_3",
  suffix = "12m_rule_3",
  max_date_var = "max_adherence_date_12m"
)

### Adherence drug combo

mpr_combo_rule_1 <- compute_mpr(
  duration_col = "duration_rule_1",
  suffix = "combo_rule_1",
  max_date_var = "max_adherence_date_combo_resp"
)

mpr_combo_rule_2 <- compute_mpr(
  duration_col = "duration_rule_2",
  suffix = "combo_rule_2",
  max_date_var = "max_adherence_date_combo_resp"
)

mpr_combo_rule_3 <- compute_mpr(
  duration_col = "duration_rule_3",
  suffix = "combo_rule_3",
  max_date_var = "max_adherence_date_combo_resp"
)





# 
# adherence_compared <- drug_class_start_stop %>%
#   select(patid, drug_class, dstartdate_class) %>%
#   
#   left_join(mpr_12m_rule2 %>% select(patid, drug_class, dstartdate_class, MPR_12m_rule2),
#             by = c("patid", "drug_class", "dstartdate_class")) %>%
#   
#   left_join(mpr_12m_rule3 %>% select(patid, drug_class, dstartdate_class, MPR_12m_rule3),
#             by = c("patid", "drug_class", "dstartdate_class")) %>%
#   
#   left_join(mpr_combo_rule2 %>% select(patid, drug_class, dstartdate_class, MPR_combo_rule2),
#             by = c("patid", "drug_class", "dstartdate_class")) %>%
#   
#   left_join(mpr_combo_rule3 %>% select(patid, drug_class, dstartdate_class, MPR_combo_rule3),
#             by = c("patid", "drug_class", "dstartdate_class")) %>%
#   
#   analysis$cached("adherence_compared",
#                   indexes = c("patid", "drug_class", "dstartdate_class"))
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 

# 
# ############################################################################################
# 
# ## Delete below
# 
# # This is an investigation on weird numbers of adherence that we are getting
# 
# 
# adherence_local <- adherence %>% collect()
# 
# adherence_summaries <- adherence_local %>%
#   mutate(
#     MPR_cat = case_when(
#       is.na(MPR) ~ "NA",
#       MPR < 20 ~ "<20%",
#       MPR > 120 ~ ">120%",
#       TRUE ~ "20%-120%"
#     )
#   )
# 
# table(adherence_summaries %>% select(MPR_cat)) %>% prop.table() * 100
# # Summaries (n = 5185629)
# ## <20% = 2.05%
# ## 20-120% = 72.20%
# ## >120% = 15.22%
# ## NA = 10.53%
# 
# 
# adherence_summaries %>%
#   select(`Drug Taken` = drug_class, `MPR` = MPR_cat) %>%
#   table() %>%
#   prop.table(1) * 100
# #           MPR
# # Drug Taken       <20%      >120%   20%-120%         NA
# # Acarbose  2.3303848 17.0849984 68.2906021 12.2940146
# # DPP4      0.6818522 18.2868932 80.3722161  0.6590385
# # GIPGLP1   0.0000000 88.2352941 11.7647059  0.0000000
# # Glinide   2.7604499 15.7915418 64.7723366 16.6756717
# # GLP1      6.4727960 13.1264631 69.9069573 10.4937836
# # INS       3.8442636  8.2760474 44.1012197 43.7784693
# # MFN       1.6574500 14.4238622 79.5571150  4.3615728
# # SGLT2     0.4833701 18.0835064 81.2137540  0.2193694
# # SU        2.0677758 19.2888854 71.8167031  6.8266358
# # TZD       1.0234672 19.3235899 76.5802598  3.0726831
# 
# 
# # investigate who has MPR low or high or missing for main drugs
# 
# is.integer64 <- function(x){
#   class(x)=="integer64"
# }
# 
# set.seed(1)
# adherence_summaries %>%
#   filter(drug_class %in% c("SGLT2", "GLP1", "DPP4", "TZD", "SU", "MFN")) %>%
#   group_by(drug_class, MPR_cat) %>%
#   slice_sample(n = 1)
# 
# 
# ## create a shorter version of the adherence_coverage_interim_1 table with
# ##  just the patients of interest for easier investigation
# 
# adherence_investigation_2 <- drug_class_start_stop %>%
#   filter(
#     (patid == "6152654221323" & drug_class == "DPP4" & dstartdate_class == "2013-02-15") |
#       (patid == "2848896721029" & drug_class == "DPP4" & dstartdate_class == "2015-01-13") | # interesting patient
#       (patid == "6524728120939" & drug_class == "DPP4" & dstartdate_class == "2013-02-22") |
#       (patid == "11623844721932" & drug_class == "DPP4" & dstartdate_class == "2010-03-05") |
#       (patid == "12081886521843" & drug_class == "GLP1" & dstartdate_class == "2023-05-04") |
#       (patid == "2561746320985" & drug_class == "GLP1" & dstartdate_class == "2011-07-06") |
#       (patid == "12437633220446" & drug_class == "GLP1" & dstartdate_class == "2023-09-07") |
#       (patid == "5494342221149" & drug_class == "GLP1" & dstartdate_class == "2013-12-11") |
#       (patid == "3255633321168" & drug_class == "MFN" & dstartdate_class == "2016-02-18") |
#       (patid == "2465556420503" & drug_class == "MFN" & dstartdate_class == "2009-06-05") |
#       (patid == "1959794220888" & drug_class == "MFN" & dstartdate_class == "2013-05-21") |
#       (patid == "11923399621798" & drug_class == "MFN" & dstartdate_class == "2017-02-06") |
#       (patid == "285820920458" & drug_class == "SGLT2" & dstartdate_class == "2022-10-26") |
#       (patid == "12266031521945" & drug_class == "SGLT2" & dstartdate_class == "2017-10-16") |
#       (patid == "3283483321212" & drug_class == "SGLT2" & dstartdate_class == "2021-03-11") |
#       (patid == "1848451420870" & drug_class == "SGLT2" & dstartdate_class == "2014-07-17") |
#       (patid == "11028307820468" & drug_class == "SU" & dstartdate_class == "2022-09-20") |
#       (patid == "11784866221758" & drug_class == "SU" & dstartdate_class == "1996-05-14") |
#       (patid == "6438230221229" & drug_class == "SU" & dstartdate_class == "2013-05-31") |
#       (patid == "2869282220112" & drug_class == "SU" & dstartdate_class == "2005-06-02") |
#       (patid == "11876771121453" & drug_class == "TZD" & dstartdate_class == "2003-09-03") |
#       (patid == "6681565921609" & drug_class == "TZD" & dstartdate_class == "2015-10-16") |
#       (patid == "11826500521913" & drug_class == "TZD" & dstartdate_class == "2012-06-28") |
#       (patid == "11516036721917" & drug_class == "TZD" & dstartdate_class == "2001-10-17")
#   ) %>%
#   # Retain identifiers and therapy window boundaries
#   select(patid, drug_class, dstartdate_class, dstopdate_class) %>%
#   
#   # Compute the 1-year post-initiation cut-off for truncating adherence periods
#   mutate(one_year_post_initiation = sql("date_add(dstartdate_class, interval 365 day)")) %>%
#   
#   # Attach 12-month HbA1c response if available
#   left_join(
#     post12m_hba1c %>%
#       rename(dstartdate_class = dstartdate) %>%   # Ensures exact match to therapy start date
#       select(patid, drug_class, drug_substance, dstartdate_class, post_biomarker_12mdate),
#     by = c("patid", "drug_class", "dstartdate_class")
#   ) %>%
#   
#   # Attach 6-month HbA1c response if 12-month is missing
#   left_join(
#     post6m_hba1c %>%
#       rename(dstartdate_class = dstartdate) %>%   # Same rationale as above
#       select(patid, drug_class, dstartdate_class, post_biomarker_6mdate),
#     by = c("patid", "drug_class", "dstartdate_class")
#   ) %>%
#   
#   # Determine the final adherence end date based on hierarchy of rules
#   mutate(
#     max_adherence_date = case_when(
#       # Primary: if a 12-month outcome exists, the adherence window ends there
#       !is.na(post_biomarker_12mdate) ~ post_biomarker_12mdate,
#       
#       # Secondary: if 12-month missing but 6-month exists, end at 6-month date
#       !is.na(post_biomarker_6mdate)  ~ post_biomarker_6mdate,
#       
#       # Otherwise: end at the earliest of stop date or 1-year cut-off
#       TRUE ~ pmin(dstopdate_class, one_year_post_initiation, na.rm = TRUE)
#     )
#   ) %>%
#   inner_join(
#     all_scripts_long_duration_clean, by = c("patid", "drug_class")
#   ) %>%
#   # select(patid, drug_class, dstartdate_class, max_adherence_date, date, quantity, duration, duration_rule_1, duration_rule_2, duration_cleaned, daily_dose) %>%
#   filter(date >= dstartdate_class & date < max_adherence_date) %>%
#   mutate(coverage = duration_cleaned) %>%
#   group_by(patid, drug_class, dstartdate_class) %>%
#   mutate(days_covered = sum(coverage, na.rm = TRUE)) %>%
#   ungroup() %>%
#   mutate(days_passed = datediff(max_adherence_date, dstartdate_class)) %>%
#   mutate(MPR = days_covered / days_passed * 100) %>%
#   analysis$cached("delete_adherence_inves_2", indexes = c("patid", "drug_class", "dstartdate_class"))



