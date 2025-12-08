
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



############################################################################################

# # This is the translation from the stata code to R
# 
# # Calculate Stata-style MPR variants using Rule 3 and 12-month period:
# #   - MPR_raw: The base fixed-period MPR (similar to MPR_12m_rule_3)
# #   - MPR_excl_m: MPR with standard data quality exclusions (MPR_m)
# #   - MPR_excl_t: MPR excluding missing days from the denominator (MPR_t)
# #   - MPR_minus1st: MPR excluding the first prescription
# 
# # Prepare script-level indicators and join end dates for use in the calculation function
# base_data_for_stata_mpr <- adherence_relevant_scripts_duration %>%
#   select(
#     patid, drug_class, dstartdate_class, date,
#     quantity, daily_dose, duration_rule_3
#   ) %>%
#   
#   # Calculate necessary prescription-level flags for exclusions
#   mutate(
#     is_valid_px = ifelse(!is.na(quantity) & quantity > 0 & !is.na(daily_dose) & daily_dose > 0, TRUE, FALSE),
#     is_missing_data = ifelse(is_valid_px == TRUE, FALSE, TRUE),
#     coverage = duration_rule_3
#   ) %>%
#   
#   # Add prescription counter (pdecount) and first prescription details
#   group_by(patid, drug_class, dstartdate_class) %>%
#   dbplyr::window_order(date) %>%
#   mutate(
#     pdecount = row_number(),
#     days1stpx = ifelse(pdecount == 1, coverage, NA),
#     gap1stpx = ifelse(pdecount == 1, datediff(lead(date), date), NA)
#   ) %>%
#   ungroup() %>%
#   
#   # Join the pre-calculated end dates
#   inner_join(
#     adherence_start_stop %>%
#       select(patid, drug_class, dstartdate_class, max_adherence_date_12m, max_adherence_date_combo_resp),
#     by = c("patid", "drug_class", "dstartdate_class")
#   ) %>%
#   analysis$cached("compute_mpr_stata_base_scripts_with_dates", indexes = c("patid", "drug_class", "dstartdate_class"))
# 
# 
# ## Reusable Function for Stata MPR Calculations
# 
# # This function uses non-standard evaluation (!!sym) to handle the period_end_col string
# calculate_stata_mpr_variants <- function(
#     data, 
#     period_end_col, 
#     prefix,
#     cache_name_agg
# ) {
#   browser()
#   period_end_sym <- sym(period_end_col) 
#   
#   # --- INTERIM CACHE 1: AGGREGATION ---
#   # Perform the computationally heavy grouping and summation/aggregation.
#   mpr_components_agg <- data %>%
#     # Filter prescriptions relevant to the current period
#     filter(date >= dstartdate_class & date < !!period_end_sym) %>%
#     
#     group_by(patid, drug_class, dstartdate_class, !!period_end_sym) %>%
#     summarise(
#       total_coverage = sum(coverage, na.rm = TRUE),
#       days_in_window = datediff(!!period_end_sym, dstartdate_class),
#       
#       # Exclusions components
#       ptndd0y1 = sum(!is.na(daily_dose) & daily_dose == 0, na.rm = TRUE),
#       ptqty0y1 = sum(!is.na(quantity) & quantity == 0, na.rm = TRUE),
#       numvalidpxy1 = sum(is_valid_px, na.rm = TRUE),
#       total_missing_data_px = sum(is_missing_data, na.rm = TRUE),
#       
#       # First prescription values (needed for MPR_minus1st)
#       days1stpx = max(days1stpx, na.rm = TRUE),
#       gap1stpx = max(gap1stpx, na.rm = TRUE),
#       
#       .groups = 'drop'
#     ) %>%
#     
#     # *** INTERIM CACHE POINT ***
#     # The cache name now uses the provided cache_name_agg argument, e.g., "compute_mpr_stata_12m_agg"
#     analysis$cached(cache_name_agg, indexes = c("patid", "drug_class", "dstartdate_class"))
#   
#   # --- FINAL CALCULATIONS ---
#   mpr_components <- mpr_components_agg %>%
#     
#     # Calculate Base MPR
#     mutate(days_in_window = ifelse(is.na(days_in_window) | days_in_window <= 0, NA, days_in_window)) %>%
#     mutate(!!paste0(prefix, "_raw") := total_coverage / days_in_window * 100) %>%
#     
#     # --- Calculate MPR_excl_m (Adherence with Exclusions) ---
#     mutate(
#       !!paste0(prefix, "_excl_m") := !!sym(paste0(prefix, "_raw")),
#       !!paste0(prefix, "_excl_m") := ifelse(ptndd0y1 > 0 | ptqty0y1 > 0, NA, !!sym(paste0(prefix, "_excl_m"))),
#       !!paste0(prefix, "_excl_m") := ifelse(numvalidpxy1 < 3, NA, !!sym(paste0(prefix, "_excl_m")))
#     ) %>%
#     
#     # --- Calculate MPR_excl_t (Excluding Missing Periods) ---
#     mutate(
#       !!paste0(prefix, "_excl_t") := !!sym(paste0(prefix, "_raw")),
#       !!paste0(prefix, "_excl_t") := ifelse(is.na(!!sym(paste0(prefix, "_excl_m"))), NA, !!sym(paste0(prefix, "_excl_t"))),
#       !!paste0(prefix, "_excl_t") := ifelse(total_missing_data_px > 90, NA, !!sym(paste0(prefix, "_excl_t")))
#     ) %>%
#     
#     # --- Calculate MPR_minus1st (First Entry Removed) ---
#     mutate(
#       covy1miss1st = total_coverage - days1stpx,
#       daysy1miss1st = days_in_window - gap1stpx,
#       
#       !!paste0(prefix, "_minus1st") := ifelse(
#         !is.na(days1stpx) & daysy1miss1st > 0,
#         covy1miss1st / daysy1miss1st * 100,
#         NA
#       ),
#       !!paste0(prefix, "_minus1st") := ifelse(is.na(!!sym(paste0(prefix, "_excl_m"))), NA, !!sym(paste0(prefix, "_minus1st")))
#     ) %>%
#     
#     select(patid, drug_class, dstartdate_class, starts_with(prefix))
#   
#   return(mpr_components)
# }
# 
# ## 3. Apply the function to both periods with explicit cache names
# 
# # A. Fixed 12m Period
# mpr_stata_12m <- calculate_stata_mpr_variants(
#   data = base_data_for_stata_mpr,
#   period_end_col = "max_adherence_date_12m",
#   prefix = "MPR_12m_stata",
#   cache_name_agg = "compute_mpr_stata_12m_agg"
# ) %>% analysis$cached("compute_mpr_stata_12m_final", indexes = c("patid", "drug_class", "dstartdate_class"))
# 
# # B. Combo Response Max Adherence Period
# mpr_stata_combo <- calculate_stata_mpr_variants(
#   data = base_data_for_stata_mpr,
#   period_end_col = "max_adherence_date_combo_resp",
#   prefix = "MPR_combo_stata",
#   cache_name_agg = "compute_mpr_stata_combo_agg"
# ) %>% analysis$cached("compute_mpr_stata_combo_final", indexes = c("patid", "drug_class", "dstartdate_class"))

############################################################################################

# Prepare scripts to ensure scripts are valid

adherence_relevant_scripts_prepared <- adherence_relevant_scripts_duration %>%
  mutate(
    is_valid_px = ifelse(!is.na(duration_rule_3), TRUE, FALSE),
    is_missing_data = ifelse(is_valid_px == TRUE, FALSE, TRUE),
    duration_rule_3 = coalesce(duration_rule_3, 0)
  ) %>%
  analysis$cached("adherence_relevant_scripts_prepared", indexes = c("patid", "drug_class", "dstartdate_class"))

# Apply stockpiling rules

base_data_stockpilling <- adherence_relevant_scripts_prepared %>%
  group_by(patid, drug_class, dstartdate_class) %>%
  dbplyr::window_order(date) %>%
  mutate(
    # 1. stockpilling logic
    # Calculate when the previous script finished
    prev_end_date = lag(sql("date_add(date, interval duration_rule_3 - 1 day)")),
    
    # If overlap, shift start date to avoid double counting
    effective_start_date = ifelse(!is.na(prev_end_date) | date <= prev_end_date, sql("date_add(prev_end_date, interval 1 day)"), date),
    
    # 2. gap logic
    # calculate days until the next prescription start
    next_start_date = lead(effective_start_date, order_by = effective_start_date),
    
    # Time to gap to next script
    days_until_next = datediff(next_start_date, effective_start_date),
  ) %>%
  ungroup() %>%
  analysis$cached("base_data_stockpilling", indexes = c("patid", "drug_class", "dstartdate_class"))

mpr_stata_12m <- base_data_stockpilling %>%
  left_join(
    adherence_start_stop, by = c("patid", "drug_class", "dstartdate_class")
  ) %>%
  filter(effective_start_date >= dstartdate_class & effective_start_date < max_adherence_date_12m) %>%
  group_by(patid, drug_class, dstartdate_class, max_adherence_date_12m) %>%
  summarise(
    # numerator: total supply
    total_coverage = sum(duration_rule_3, na.rm = TRUE),
    
    # denominator: total time window
    total_days_in_window = datediff(max_adherence_date_12m, dstartdate_class),
    
    # count invalid prescriptions
    count_invalid_px = sum(is_missing_data, na.rm = TRUE),
    count_valid_px = sum(is_valid_px, na.rm = TRUE),
    
    # sum of days associated with missing data
    total_miss_days = sum(ifelse(is_missing_data == 1, days_until_next, 0), na.rm = TRUE),
    
    # we need the duration and gap of the very first script
    first_px_duration = sql("CAST(SUBSTRING_INDEX(GROUP_CONCAT(duration_rule_3 ORDER BY effective_start_date), ',', 1) AS UNSIGNED)"),
    first_px_gap = sql("CAST(SUBSTRING_INDEX(GROUP_CONCAT(days_until_next ORDER BY effective_start_date), ',', 1) AS UNSIGNED)")
  ) %>%
  # calculate the variables for MPR
  mutate(
    # raw adherence
    MPR_12m_raw = (total_coverage / total_days_in_window) * 100,
    
    # adherence M (strict exclusion)
    MPR_12m_strict = case_when(
      count_invalid_px > 0 ~ NA_real_,
      count_valid_px < 3 ~ NA_real_,
      TRUE ~ adherence_raw
    ),
    
    # adherence T (denominator adjusted)
    # Denominator becomes: (Total Window - Days Missing)
    denom_t = total_days_in_window - coalesce(total_miss_days, 0),
    MPR_12m_adj = case_when(
      is.na(adherence_m) ~ NA_real_,      # Apply M exclusions first
      total_miss_days > 90 ~ NA_real_,    # Exclude if >90 days missing [cite: 15]
      denom_t > 0 ~ (total_coverage / denom_t) * 100,
      TRUE ~ NA_real_
    ),
    
    # Adherence Minus 1st [cite: 17]
    # Remove first script from Numerator and Denominator
    num_min1 = total_coverage - first_px_duration,
    denom_min1 = total_days_in_window - first_px_gap,
    MPR_12m_minus1st = case_when(
      is.na(adherence_m) ~ NA_real_,
      denom_min1 > 0 ~ (num_min1 / denom_min1) * 100,
      TRUE ~ NA_real_
    )
    
  ) %>%
  select(patid, drug_class, dstartdate_class, max_adherence_date_12m, 
         MPR_12m_raw, MPR_12m_strict, MPR_12m_adj, MPR_12m_minus1st, 
         total_days_in_window, total_miss_days, count_valid_px, count_invalid_px) %>%
  
  analysis$cached("compute_mpr_stata_12m", indexes = c("patid", "drug_class", "dstartdate_class"))


mpr_stata_combo <- base_data_stockpilling %>%
  left_join(
    adherence_start_stop, by = c("patid", "drug_class", "dstartdate_class")
  ) %>%
  filter(effective_start_date >= dstartdate_class & effective_start_date < max_adherence_date_combo_resp) %>%
  group_by(patid, drug_class, dstartdate_class, max_adherence_date_combo_resp) %>%
  summarise(
    # numerator: total supply
    total_coverage = sum(duration_rule_3, na.rm = TRUE),
    
    # denominator: total time window
    total_days_in_window = datediff(max_adherence_date_combo_resp, dstartdate_class),
    
    # count invalid prescriptions
    count_invalid_px = sum(is_missing_data, na.rm = TRUE),
    count_valid_px = sum(is_valid_px, na.rm = TRUE),
    
    # sum of days associated with missing data
    total_miss_days = sum(ifelse(is_missing_data == 1, days_until_next, 0), na.rm = TRUE),
    
    # we need the duration and gap of the very first script
    first_px_duration = sql("CAST(SUBSTRING_INDEX(GROUP_CONCAT(duration_rule_3 ORDER BY effective_start_date), ',', 1) AS UNSIGNED)"),
    first_px_gap = sql("CAST(SUBSTRING_INDEX(GROUP_CONCAT(days_until_next ORDER BY effective_start_date), ',', 1) AS UNSIGNED)")
  ) %>%
  # calculate the variables for MPR
  mutate(
    # raw adherence
    MPR_combo_raw = (total_coverage / total_days_in_window) * 100,
    
    # adherence M (strict exclusion)
    MPR_combo_strict = case_when(
      count_invalid_px > 0 ~ NA_real_,
      count_valid_px < 3 ~ NA_real_,
      TRUE ~ adherence_raw
    ),
    
    # adherence T (denominator adjusted)
    # Denominator becomes: (Total Window - Days Missing)
    denom_t = total_days_in_window - coalesce(total_miss_days, 0),
    MPR_combo_adj = case_when(
      is.na(adherence_m) ~ NA_real_,      # Apply M exclusions first
      total_miss_days > 90 ~ NA_real_,    # Exclude if >90 days missing [cite: 15]
      denom_t > 0 ~ (total_coverage / denom_t) * 100,
      TRUE ~ NA_real_
    ),
    
    # Adherence Minus 1st [cite: 17]
    # Remove first script from Numerator and Denominator
    num_min1 = total_coverage - first_px_duration,
    denom_min1 = total_days_in_window - first_px_gap,
    MPR_combo_minus1st = case_when(
      is.na(adherence_m) ~ NA_real_,
      denom_min1 > 0 ~ (num_min1 / denom_min1) * 100,
      TRUE ~ NA_real_
    )
    
  ) %>%
  select(patid, drug_class, dstartdate_class, max_adherence_date_combo_resp, 
         MPR_combo_raw, MPR_combo_strict, MPR_combo_adj, MPR_combo_minus1st, 
         total_days_in_window, total_miss_days, count_valid_px, count_invalid_px) %>%
  
  analysis$cached("compute_mpr_stata_combo", indexes = c("patid", "drug_class", "dstartdate_class"))



############################################################################################






adherence_compared <- drug_class_start_stop %>%
  select(patid, drug_class, dstartdate_class) %>%
  
  # rule 1
  left_join(mpr_12m_rule_1 %>% select(patid, drug_class, dstartdate_class, MPR_12m_rule_1),
            by = c("patid", "drug_class", "dstartdate_class")) %>%
  
  left_join(mpr_combo_rule_1 %>% select(patid, drug_class, dstartdate_class, MPR_combo_rule_1),
            by = c("patid", "drug_class", "dstartdate_class")) %>%
  
  analysis$cached("adherence_compared_interim_1",
                  indexes = c("patid", "drug_class", "dstartdate_class")) %>%
  
  left_join(mpr_12m_rule_2 %>% select(patid, drug_class, dstartdate_class, MPR_12m_rule_2),
            by = c("patid", "drug_class", "dstartdate_class")) %>%
  
  left_join(mpr_combo_rule_2 %>% select(patid, drug_class, dstartdate_class, MPR_combo_rule_2),
            by = c("patid", "drug_class", "dstartdate_class")) %>%
  
  analysis$cached("adherence_compared_interim_2",
                  indexes = c("patid", "drug_class", "dstartdate_class")) %>%
  
  left_join(mpr_12m_rule_3 %>% select(patid, drug_class, dstartdate_class, MPR_12m_rule_3),
            by = c("patid", "drug_class", "dstartdate_class")) %>%

  left_join(mpr_combo_rule_3 %>% select(patid, drug_class, dstartdate_class, MPR_combo_rule_3),
            by = c("patid", "drug_class", "dstartdate_class")) %>%

  analysis$cached("adherence_compared_interim_3",
                  indexes = c("patid", "drug_class", "dstartdate_class")) %>%
  
  # # --- NEW: Stata-based MPR variants (12m Fixed) ---
  # left_join(mpr_stata_12m, by = c("patid", "drug_class", "dstartdate_class")) %>%
  # 
  # # --- NEW: Stata-based MPR variants (Combo Response Max Adherence) ---
  # left_join(mpr_stata_combo, by = c("patid", "drug_class", "dstartdate_class")) %>%
  # 
  # analysis$cached("adherence_compared_interim_4",
  #                 indexes = c("patid", "drug_class", "dstartdate_class"))

# count(adherence_compared)
# 5,990,512







############################################################################################

# ##
# # Custom dosages
# ##
# delete_dosages <- adherence_relevant_scripts %>%
#   select(dosageid) %>%
#   distinct() %>%
#   left_join(
#     cprd$tables$commonDose, by = c("dosageid")
#   ) %>%
#   analysis$cached("delete_dosage_information", index = c("dosageid"))
# 
# count(delete_dosages)
# # 960,937
# 
# 
# delete_dosages_2 <- adherence_relevant_scripts %>%
#   select(dosageid) %>%
#   distinct() %>%
#   inner_join(
#     cprd$tables$commonDose, by = c("dosageid")
#   ) %>%
#   analysis$cached("delete_dosage_information_2", index = c("dosageid"))
# 
# count(delete_dosages_2)
# # 20,508
# 
# # test <- delete_dosages_2 %>% collect()
# # 
# # readr::write_csv(delete_dosages_2 %>% collect(), "03-Treatment-response-(MASTERMIND)/commonDose_table_shorter.csv")



##
# Below is an investigation on weird numbers of adherence that we are getting
##

# load libraries
library(purrr)

adherence_compared_local<- adherence_compared %>%
  collect()


## Number of patients (and %) with adherence categories
# List of MPR columns
mpr_cols <- adherence_compared_local %>%
  select(starts_with("MPR")) %>%
  colnames()

# Total N of dataset
N_total <- nrow(adherence_compared_local)

# Function to categorize MPR
categorise_mpr <- function(x) {
  case_when(
    is.na(x) ~ "NA",
    x < 20 ~ "<20%",
    x > 120 ~ ">120%",
    x >= 20 & x <80 ~ "20%-80%",
    TRUE ~ "80%-120%",
    # TRUE ~ "20%-120%"
  )
}

# Generate counts + % relative to full dataset
mpr_summary_list <- map(mpr_cols, function(col) {
  adherence_compared_local %>%
    transmute(MPR_cat = categorise_mpr(.data[[col]])) %>%
    count(MPR_cat) %>%
    mutate(
      pct = round(100 * n / N_total, 2),
      MPR_column = col
    )
})

# Combine all summaries
mpr_summary <- bind_rows(mpr_summary_list) %>%
  select(MPR_column, MPR_cat, n, pct) %>%
  mutate(
    n   = format(n, big.mark = ",", scientific = FALSE),
    pct = sprintf("%.1f", round(pct, 1)),
    value = paste0(n, " (", pct, "%)"),
    type = case_when(
      grepl("12m", MPR_column) ~ "12m",
      grepl("combo", MPR_column) ~ "combo"
    ),
    rule = as.numeric(sub(".*rule_", "", MPR_column))
  ) %>%
  select(MPR_column, type, rule, MPR_cat, value) %>%
  pivot_wider(
    names_from = MPR_cat,
    values_from = value
  ) %>%
  arrange(type, rule) %>%
  # select(type, rule, `<20%`, `20%-120%`, `>120%`, `NA`)  # reordered columns
  select(type, rule, `<20%`, `20%-80%`,`80%-120%`, `>120%`, `NA`)  # reordered columns

mpr_summary


# Vector of drug classes to include
selected_drugclass <- c("MFN", "SGLT2", "GLP1", "DPP4", "TZD", "SU")

# Filter data for selected drug classes
adherence_filtered <- adherence_compared_local %>%
  filter(drug_class %in% selected_drugclass)

# List of MPR columns
mpr_cols <- adherence_filtered %>%
  select(starts_with("MPR")) %>%
  colnames()

# Total N of filtered dataset
N_total <- nrow(adherence_filtered)

# Function to categorize MPR
categorise_mpr <- function(x) {
  case_when(
    is.na(x) ~ "NA",
    x < 20 ~ "<20%",
    x > 120 ~ ">120%",
    x >= 20 & x <80 ~ "20%-80%",
    TRUE ~ "80%-120%",
    # TRUE ~ "20%-120%"
  )
}

# Generate counts + % relative to filtered dataset
mpr_summary_list <- map(mpr_cols, function(col) {
  adherence_filtered %>%
    transmute(MPR_cat = categorise_mpr(.data[[col]])) %>%
    count(MPR_cat) %>%
    mutate(
      pct = round(100 * n / N_total, 2),
      MPR_column = col
    )
})

# Combine all summaries
mpr_summary <- bind_rows(mpr_summary_list) %>%
  select(MPR_column, MPR_cat, n, pct) %>%
  mutate(
    n   = format(n, big.mark = ",", scientific = FALSE),
    pct = sprintf("%.1f", round(pct, 1)),
    value = paste0(n, " (", pct, "%)"),
    type = case_when(
      grepl("12m", MPR_column) ~ "12m",
      grepl("combo", MPR_column) ~ "combo"
    ),
    rule = as.numeric(sub(".*rule_", "", MPR_column))
  ) %>%
  select(MPR_column, type, rule, MPR_cat, value) %>%
  pivot_wider(
    names_from = MPR_cat,
    values_from = value
  ) %>%
  arrange(type, rule) %>%
  # select(type, rule, `<20%`, `20%-120%`, `>120%`, `NA`)  # reordered columns
  select(type, rule, `<20%`, `20%-80%`,`80%-120%`, `>120%`, `NA`)  # reordered columns

mpr_summary



## Investigate prescription data
set.seed(123)
adherence_compared_local %>%
  select(patid, drug_class, dstartdate_class, MPR = MPR_12m_rule_3) %>%
  mutate(
    MPR_cat = case_when(
      is.na(MPR) ~ "NA",
      MPR < 20 ~ "<20%",
      MPR > 120 ~ ">120%",
      TRUE ~ "20%-120%"
    )
  ) %>% 
  group_by(MPR_cat) %>%
  sample_n(10) %>%
  ungroup() %>% View()



investigation <- adherence_relevant_scripts_duration %>%
  filter(
    (patid == "5672328821242" & drug_class == "MFN" & dstartdate_class == "2016-11-15") |
      (patid == "11868312220289" & drug_class == "DPP4" & dstartdate_class == "2009-10-06") |
      (patid == "254853620504" & drug_class == "INS" & dstartdate_class == "2016-08-02") |
      (patid == "11783100821758" & drug_class == "SGLT2" & dstartdate_class == "2022-09-21") |
      (patid == "8982268921302" & drug_class == "SGLT2" & dstartdate_class == "2022-11-15") |
      (patid == "11906722620019" & drug_class == "SU" & dstartdate_class == "2006-12-12") |
      (patid == "12219328820415" & drug_class == "SGLT2" & dstartdate_class == "2023-01-13") |
      (patid == "3133292821100" & drug_class == "SGLT2" & dstartdate_class == "2017-08-17") |
      (patid == "11871891021732" & drug_class == "MFN" & dstartdate_class == "2004-10-20") |
      (patid == "5439544121275" & drug_class == "MFN" & dstartdate_class == "2012-08-24") |
      (patid == "647663620276" & drug_class == "DPP4" & dstartdate_class == "2022-01-21") |
      (patid == "5882165921405" & drug_class == "MFN" & dstartdate_class == "2014-03-20") |
      (patid == "5415413820370" & drug_class == "SU" & dstartdate_class == "1996-09-30") |
      (patid == "12082858021653" & drug_class == "MFN" & dstartdate_class == "2006-12-13") |
      (patid == "972502520348" & drug_class == "INS" & dstartdate_class == "2012-01-13") |
      (patid == "1023829920622" & drug_class == "SU" & dstartdate_class == "1996-07-10") |
      (patid == "1786490920431" & drug_class == "SU" & dstartdate_class == "2002-05-31") |
      (patid == "11637821121717" & drug_class == "MFN" & dstartdate_class == "2009-08-18") |
      (patid == "600764120139" & drug_class == "SU" & dstartdate_class == "2021-02-17") |
      (patid == "1982393020823" & drug_class == "INS" & dstartdate_class == "2009-01-29") |
      (patid == "6245297921098" & drug_class == "MFN" & dstartdate_class == "2012-01-17") |
      (patid == "5817864721465" & drug_class == "INS" & dstartdate_class == "2017-05-22") |
      (patid == "12474602620915" & drug_class == "DPP4" & dstartdate_class == "2016-11-02") |
      (patid == "5593044121301" & drug_class == "TZD" & dstartdate_class == "2006-11-22") |
      (patid == "912513820210" & drug_class == "DPP4" & dstartdate_class == "2014-02-27") |
      (patid == "2575923720424" & drug_class == "DPP4" & dstartdate_class == "2015-05-29") |
      (patid == "536347820148" & drug_class == "MFN" & dstartdate_class == "2020-03-04") |
      (patid == "5519442821346" & drug_class == "DPP4" & dstartdate_class == "2018-03-08") |
      (patid == "5410375720108" & drug_class == "SU" & dstartdate_class == "2023-12-14") |
      (patid == "6261197621529" & drug_class == "SU" & dstartdate_class == "2006-02-22") |
      (patid == "6311559221201" & drug_class == "MFN" & dstartdate_class == "2014-09-01") |
      (patid == "12184182520240" & drug_class == "SGLT2" & dstartdate_class == "2013-12-11") |
      (patid == "6692024921629" & drug_class == "INS" & dstartdate_class == "2018-08-08") |
      (patid == "928269920114" & drug_class == "GLP1" & dstartdate_class == "2021-11-08") |
      (patid == "1196975920353" & drug_class == "TZD" & dstartdate_class == "2004-08-11") |
      (patid == "12265918821861" & drug_class == "INS" & dstartdate_class == "2017-01-09") |
      (patid == "605753520125" & drug_class == "DPP4" & dstartdate_class == "2022-09-13") |
      (patid == "6345037521311" & drug_class == "MFN" & dstartdate_class == "2004-03-03") |
      (patid == "5435548021243" & drug_class == "INS" & dstartdate_class == "1995-09-18") |
      (patid == "685635820347" & drug_class == "TZD" & dstartdate_class == "2010-02-12")
  ) %>%
  analysis$cached("delete_investigation_interim_1", indexes = c("patid", "drug_class", "dstartdate_class")) %>%
  left_join(
    mpr_12m_rule_3, by = c("patid", "drug_class", "dstartdate_class")
  ) %>%
  analysis$cached("delete_investigation_interim_2", indexes = c("patid", "drug_class", "dstartdate_class")) %>%
  filter(date >= dstartdate_class & date < max_adherence_date_12m) %>%
  analysis$cached("delete_investigation_interim_3", indexes= c("patid", "drug_class", "dstartdate_class")) %>%
  relocate(MPR_12m_rule_3, max_adherence_date_12m, duration_rule_3, duration, quantity, daily_dose, dose_unit, date, .after = dstopdate_class) %>%
  relocate(dosage_text, .before = post_index_15m)

investigation %>% 
  collect() %>% 
  arrange(MPR_12m_rule_3, patid, drug_class, dstartdate_class, date) %>%
  group_by(patid, drug_class, dstartdate_class) %>%
  mutate(ID = cur_group_id()) %>%
  relocate(ID, .before = patid) %>%
  view()



## there seems to be an error where some people's max_adherence_data is not being calculated
## duration 366



investigation <- adherence_relevant_scripts_duration %>%
  filter(
    (patid == "5672328821242" & drug_class == "MFN" & dstartdate_class == "2016-11-15") |
      (patid == "11868312220289" & drug_class == "DPP4" & dstartdate_class == "2009-10-06") |
      (patid == "254853620504" & drug_class == "INS" & dstartdate_class == "2016-08-02") |
      (patid == "11783100821758" & drug_class == "SGLT2" & dstartdate_class == "2022-09-21") |
      (patid == "8982268921302" & drug_class == "SGLT2" & dstartdate_class == "2022-11-15") |
      (patid == "11906722620019" & drug_class == "SU" & dstartdate_class == "2006-12-12") |
      (patid == "12219328820415" & drug_class == "SGLT2" & dstartdate_class == "2023-01-13") |
      (patid == "3133292821100" & drug_class == "SGLT2" & dstartdate_class == "2017-08-17") |
      (patid == "11871891021732" & drug_class == "MFN" & dstartdate_class == "2004-10-20") |
      (patid == "5439544121275" & drug_class == "MFN" & dstartdate_class == "2012-08-24") |
      (patid == "647663620276" & drug_class == "DPP4" & dstartdate_class == "2022-01-21") |
      (patid == "5882165921405" & drug_class == "MFN" & dstartdate_class == "2014-03-20") |
      (patid == "5415413820370" & drug_class == "SU" & dstartdate_class == "1996-09-30") |
      (patid == "12082858021653" & drug_class == "MFN" & dstartdate_class == "2006-12-13") |
      (patid == "972502520348" & drug_class == "INS" & dstartdate_class == "2012-01-13") |
      (patid == "1023829920622" & drug_class == "SU" & dstartdate_class == "1996-07-10") |
      (patid == "1786490920431" & drug_class == "SU" & dstartdate_class == "2002-05-31") |
      (patid == "11637821121717" & drug_class == "MFN" & dstartdate_class == "2009-08-18") |
      (patid == "600764120139" & drug_class == "SU" & dstartdate_class == "2021-02-17") |
      (patid == "1982393020823" & drug_class == "INS" & dstartdate_class == "2009-01-29") |
      (patid == "6245297921098" & drug_class == "MFN" & dstartdate_class == "2012-01-17") |
      (patid == "5817864721465" & drug_class == "INS" & dstartdate_class == "2017-05-22") |
      (patid == "12474602620915" & drug_class == "DPP4" & dstartdate_class == "2016-11-02") |
      (patid == "5593044121301" & drug_class == "TZD" & dstartdate_class == "2006-11-22") |
      (patid == "912513820210" & drug_class == "DPP4" & dstartdate_class == "2014-02-27") |
      (patid == "2575923720424" & drug_class == "DPP4" & dstartdate_class == "2015-05-29") |
      (patid == "536347820148" & drug_class == "MFN" & dstartdate_class == "2020-03-04") |
      (patid == "5519442821346" & drug_class == "DPP4" & dstartdate_class == "2018-03-08") |
      (patid == "5410375720108" & drug_class == "SU" & dstartdate_class == "2023-12-14") |
      (patid == "6261197621529" & drug_class == "SU" & dstartdate_class == "2006-02-22") |
      (patid == "6311559221201" & drug_class == "MFN" & dstartdate_class == "2014-09-01") |
      (patid == "12184182520240" & drug_class == "SGLT2" & dstartdate_class == "2013-12-11") |
      (patid == "6692024921629" & drug_class == "INS" & dstartdate_class == "2018-08-08") |
      (patid == "928269920114" & drug_class == "GLP1" & dstartdate_class == "2021-11-08") |
      (patid == "1196975920353" & drug_class == "TZD" & dstartdate_class == "2004-08-11") |
      (patid == "12265918821861" & drug_class == "INS" & dstartdate_class == "2017-01-09") |
      (patid == "605753520125" & drug_class == "DPP4" & dstartdate_class == "2022-09-13") |
      (patid == "6345037521311" & drug_class == "MFN" & dstartdate_class == "2004-03-03") |
      (patid == "5435548021243" & drug_class == "INS" & dstartdate_class == "1995-09-18") |
      (patid == "685635820347" & drug_class == "TZD" & dstartdate_class == "2010-02-12")
  ) %>%
  analysis$cached("delete_investigation_interim_1", indexes = c("patid", "drug_class", "dstartdate_class")) %>%
  left_join(
    mpr_12m_rule_3, by = c("patid", "drug_class", "dstartdate_class")
  ) %>%
  analysis$cached("delete_investigation_interim_2", indexes = c("patid", "drug_class", "dstartdate_class")) %>%
  filter(date >= dstartdate_class & date < max_adherence_date_12m) %>%
  analysis$cached("delete_investigation_interim_3", indexes= c("patid", "drug_class", "dstartdate_class")) %>%
  relocate(MPR_12m_rule_3, max_adherence_date_12m, duration_rule_3, duration, quantity, daily_dose, dose_unit, date, .after = dstopdate_class) %>%
  relocate(dosage_text, .before = post_index_15m)




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
# Summaries (n = 5185629)
## <20% = 2.05%
## 20-120% = 72.20%
## >120% = 15.22%
## NA = 10.53%
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



