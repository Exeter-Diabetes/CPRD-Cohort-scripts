
# Adds adherence for all drug class initated


############################################################################################

# Setup
require(tidyverse)
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

# Calculate duration and valid prescription rules:
#   Duration: take duration > 0 else calculate using quantity / daily_dose (daily_dose > 0, quantity > 0)

adherence_relevant_scripts_duration <- adherence_relevant_scripts %>%
  
  # Calculate cleaned duration
  mutate(
    duration_cleaned = case_when(
      # Rule 1: duration ≤ 0 → invalid → set to NA
      !is.na(duration) & duration > 0 ~ duration,
      
      # Rule 2: if duration missing but both quantity and daily_dose valid -> infer duration
      !is.na(daily_dose) & daily_dose > 0 &
        !is.na(quantity) & quantity > 0 ~ quantity / daily_dose,
      
      # Rule 3: Otherwise consider invalid
      TRUE ~ NA_real_
    )
  ) %>%

  # Label for valid and invalid prescriptions
  mutate(
    is_valid_px = ifelse(!is.na(duration_cleaned), 1, 0),
    is_invalid_px = ifelse(is_valid_px == 1, 0, 1),
    duration_cleaned = coalesce(duration_cleaned, 0)
  ) %>%
  
  # Cache
  analysis$cached("adherence_relevant_scripts_duration", indexes = c("patid", "drug_class", "dstartdate_class"))
  


############################################################################################


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
#  - Adherence connected to HbA1c, earliest of (NAME: _resphba1c)
#    - 12m HbA1c outcome
#    - 6m HbA1c outcome

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
    
    ## Stop for adherence connected to HbA1c response
    max_adherence_date_resphba1c = case_when(
      # Primary: if a 12-month outcome exists, adherence window finishes there
      !is.na(post_biomarker_12mdate) ~ post_biomarker_12mdate,
      
      # Secondary: if a 6-month outcome exists, adherence window finishes there
      !is.na(post_biomarker_6mdate) ~ post_biomarker_6mdate,
      
      # Otherwise: NA
      TRUE ~ NA_real_
      
    )
  ) %>%
  
  # Keep only what is needed for adherence evaluation
  select(patid, drug_class, dstartdate_class, max_adherence_date_12m, max_adherence_date_resphba1c) %>%
  analysis$cached("adherence_start_stop", indexes = c("patid", "drug_class", "dstartdate_class"))


############################################################################################

# Apply stockpilling rules
base_data_stockpilling <- adherence_relevant_scripts_duration %>%
  
  ## Group by patid, drug_class and dstartdate_class
  group_by(patid, drug_class, dstartdate_class) %>%
  
  ## Order by prescription dates
  dbplyr::window_order(date) %>%
  
  ## stockpilling logic
  mutate(
    # Calculate when the previous script finished
    prev_end_date = lag(sql("date_add(date, interval duration_cleaned - 1 day)")),
    
    # If overlap, shift start date to avoid double counting
    effective_start_date = ifelse(!is.na(prev_end_date) & date <= prev_end_date, sql("date_add(prev_end_date, interval 1 day)"), date),
    
    # 2. gap logic
    # calculate days until the next prescription start
    next_start_date = lead(effective_start_date, order_by = effective_start_date),
    
    # Time to gap to next script
    days_until_next = datediff(next_start_date, effective_start_date),
    
    # # Mark if this is the first prescription
    is_first_px = ifelse(row_number() == 1, TRUE, FALSE),
  ) %>%
  
  ## Remove grouping
  ungroup() %>%
  
  ## Cache
  analysis$cached("base_data_stockpilling", indexes = c("patid", "drug_class", "dstartdate_class"))




############################################################################################

# MPR variables:
## MPR_raw: sum of prescription durations / days passed
## MPR_adj: sum of prescription durations / (days passed - total days missed)
## MPR_strick: sum of prescription duration / days passed (at least 3 valid px, 0 invalid px)
## MPR_min1: sum of prescription durations / days passed (after removing values for the 1px)


# Calculate MPR rules for 12m

mpr_12m <- base_data_stockpilling %>%
  
  ## Join start and stop rules
  left_join(
    adherence_start_stop, by = c("patid", "drug_class", "dstartdate_class")
  ) %>%
  
  ## Keep only important prescriptions
  filter(effective_start_date >= dstartdate_class & effective_start_date < max_adherence_date_12m) %>%
  
  ## Cache
  analysis$cached("compute_mpr_12m_interim_1") %>%
  
  ## Group by patid, drug_class and dstartdate_class
  group_by(patid, drug_class, dstartdate_class, max_adherence_date_12m) %>%
  
  ## Summarise details for each drug period
  summarise(
    # numerator: total supply
    total_coverage = sum(duration_cleaned, na.rm = TRUE),
    
    # denominator: total time window
    total_days_in_window = datediff(max_adherence_date_12m, dstartdate_class),
    
    # count invalid prescriptions
    count_invalid_px = sum(is_invalid_px, na.rm = TRUE),
    count_valid_px = sum(is_valid_px, na.rm = TRUE),
    
    # sum of days associated with missing data
    total_miss_days = sum(ifelse(is_invalid_px == 1, days_until_next, 0), na.rm = TRUE),
    
    # # we need the duration and gap of the very first script
    first_px_duration = sum(ifelse(is_first_px == 1, duration_cleaned, 0), na.rm = TRUE),
    first_px_gap = sum(ifelse(is_first_px == 1, days_until_next, 0), na.rm = TRUE),
    
    .groups = "drop"
  ) %>%
  
  ## Cache
  analysis$cached("compute_mpr_stata_12m_interim_2") %>%
  
  ## Calculate different MPRs
  mutate(
    
    # Raw MPR
    MPR_raw_12m = (total_coverage / total_days_in_window) * 100,
    
    # Adjusted MPR
    denom_adj = total_days_in_window - coalesce(total_miss_days, 0),
    MPR_adj_12m = case_when(
      
      ### Still missing if raw missing
      is.na(MPR_raw_12m) ~ NA_real_,
      
      ### New MPR from adjusted denominator
      denom_adj > 0 ~ (total_coverage / denom_adj) * 100,
      
      ### Otherwise: NA
      TRUE ~ NA_real_
      
    ),
    
    # Strick MPR
    MPR_strict_12m = case_when(
      
      ### If invalid px, then NA
      count_invalid_px > 0 ~ NA_real_,
      
      ### If less than 3 px, then NA
      count_valid_px < 3 ~ NA_real_,
      
      ### Otherwise: MPR_raw
      TRUE ~ MPR_raw_12m
    ),
    
    # Minus 1st PX MPR
    num_min1 = total_coverage - first_px_duration,
    denom_min1 = total_days_in_window - first_px_gap,
    MPR_min1_12m = case_when(
      
      ### Still missing if raw missing
      is.na(MPR_raw_12m) ~ NA_real_,
      
      ### New MPR from min1 denominator
      denom_min1 > 0 ~ (num_min1 / denom_min1) * 100,
      
      ### Otherwise: NA
      TRUE ~ NA_real_
    )
  ) %>%
  
  ## Select important variables
  select(
    patid, drug_class, dstartdate_class, max_adherence_date_12m,
    MPR_raw_12m, MPR_adj_12m, MPR_strict_12m, MPR_min1_12m,
    total_days_in_window, total_miss_days, count_valid_px, count_invalid_px
  ) %>%
  
  ## Cache
  analysis$cached("compute_mpr_12m", indexes = c("patid", "drug_class", "dstartdate_class"))
  


# Calculate MPR rules for resphba1c

mpr_resphba1c <- base_data_stockpilling %>%
  
  ## Join start and stop rules
  left_join(
    adherence_start_stop, by = c("patid", "drug_class", "dstartdate_class")
  ) %>%
  
  ## Keep only important prescriptions
  filter(effective_start_date >= dstartdate_class & effective_start_date < max_adherence_date_resphba1c) %>%
  
  ## Cache
  analysis$cached("compute_mpr_resphba1c_interim_1") %>%
  
  ## Group by patid, drug_class and dstartdate_class
  group_by(patid, drug_class, dstartdate_class, max_adherence_date_resphba1c) %>%
  
  ## Summarise details for each drug period
  summarise(
    # numerator: total supply
    total_coverage = sum(duration_cleaned, na.rm = TRUE),
    
    # denominator: total time window
    total_days_in_window = datediff(max_adherence_date_resphba1c, dstartdate_class),
    
    # count invalid prescriptions
    count_invalid_px = sum(is_invalid_px, na.rm = TRUE),
    count_valid_px = sum(is_valid_px, na.rm = TRUE),
    
    # sum of days associated with missing data
    total_miss_days = sum(ifelse(is_invalid_px == 1, days_until_next, 0), na.rm = TRUE),
    
    # # we need the duration and gap of the very first script
    first_px_duration = sum(ifelse(is_first_px == 1, duration_cleaned, 0), na.rm = TRUE),
    first_px_gap = sum(ifelse(is_first_px == 1, days_until_next, 0), na.rm = TRUE),
    
    .groups = "drop"
  ) %>%
  
  ## Cache
  analysis$cached("compute_mpr_stata_resphba1c_interim_2") %>%
  
  ## Calculate different MPRs
  mutate(
    
    # Raw MPR
    MPR_raw_resphba1c = (total_coverage / total_days_in_window) * 100,
    
    # Adjusted MPR
    denom_adj = total_days_in_window - coalesce(total_miss_days, 0),
    MPR_adj_resphba1c = case_when(
      
      ### Still missing if raw missing
      is.na(MPR_raw_resphba1c) ~ NA_real_,
      
      ### New MPR from adjusted denominator
      denom_adj > 0 ~ (total_coverage / denom_adj) * 100,
      
      ### Otherwise: NA
      TRUE ~ NA_real_
      
    ),
    
    # Strick MPR
    MPR_strict_resphba1c = case_when(
      
      ### If invalid px, then NA
      count_invalid_px > 0 ~ NA_real_,
      
      ### If less than 3 px, then NA
      count_valid_px < 3 ~ NA_real_,
      
      ### Otherwise: MPR_raw
      TRUE ~ MPR_raw_resphba1c
    ),
    
    # Minus 1st PX MPR
    num_min1 = total_coverage - first_px_duration,
    denom_min1 = total_days_in_window - first_px_gap,
    MPR_min1_resphba1c = case_when(
      
      ### Still missing if raw missing
      is.na(MPR_raw_resphba1c) ~ NA_real_,
      
      ### New MPR from min1 denominator
      denom_min1 > 0 ~ (num_min1 / denom_min1) * 100,
      
      ### Otherwise: NA
      TRUE ~ NA_real_
    )
  ) %>%
  
  ## Select important variables
  select(
    patid, drug_class, dstartdate_class, max_adherence_date_resphba1c,
    MPR_raw_resphba1c, MPR_adj_resphba1c, MPR_strict_resphba1c, MPR_min1_resphba1c,
    total_days_in_window, total_miss_days, count_valid_px, count_invalid_px
  ) %>%
  
  ## Cache
  analysis$cached("compute_mpr_resphba1c", indexes = c("patid", "drug_class", "dstartdate_class"))



############################################################################################

adherence <- drug_class_start_stop %>%
  
  ## Select important variables
  select(patid, drug_class, dstartdate_class) %>%
  
  # Join 12m adherence
  left_join(
    compute_mpr_12m %>%
      select(
        patid, drug_class, dstartdate_class, 
        MPR_raw_12m, MPR_adj_12m, MPR_strict_12m, MPR_min1_12m
      ),
    by = c("patid", "drug_class", "dstartdate_class")
  ) %>%
  
  ## Join resphba1c adherence
  left_join(
    compute_mpr_resphba1c %>%
      select(
        patid, drug_class, dstartdate_class, 
        MPR_raw_resphba1c, MPR_adj_resphba1c, MPR_strict_resphba1c, MPR_min1_resphba1c
      ),
    by = c("patid", "drug_class", "dstartdate_class")
  ) %>%
  
  ## Cache
  analysis$cached("adherence", indexes = c("patid", "drug_class", "dstartdate_class"))


