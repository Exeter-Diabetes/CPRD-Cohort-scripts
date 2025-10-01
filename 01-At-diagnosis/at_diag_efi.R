
# Calculates electronic frailty index (https://pubmed.ncbi.nlm.nih.gov/26944937/) at index date
# Polypharmacy assumed to be 1

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "01/06/2024")

analysis = cprd$analysis("at_diag")


############################################################################################

# Create a vector of all codelist names that start with "efi_"
efi_deficits <- grep("^efi_", names(codes), value = TRUE)

# List of deficit names to shorten
short_deficit_map <- list(
  "efi_mobility_and_transfer_problems" = "efi_mobility_transfer"
)


# Function to shorten table name to avoid 64-character limit;
# otherwise use the original name
get_short_deficit <- function(deficit) {
  if (deficit %in% names(short_deficit_map)) {
    return(short_deficit_map[[deficit]])
  } else {
    return(deficit)
  }
}


# Pull out all raw code instances and cache with 'all_patid' prefix

analysis <- cprd$analysis("all_patid")

for (deficit in efi_deficits) {
  
  # If the codelist is not empty
  if (length(codes[[deficit]]) > 0) {
    
    print(paste("making", deficit, "medcode table"))
    
    # Shorten deficit name
    deficit <- get_short_deficit(deficit)
    
    # Name intermediate table (e.g., "raw_efi_anaemia_haematinic_deficiency_medcodes")
    raw_tablename <- paste0("raw_", deficit, "_medcodes")
    
    # Get all relevant observation rows for this deficit
    data <- cprd$tables$observation %>%
      inner_join(codes[[deficit]], by = "medcodeid") %>%
      analysis$cached(
        raw_tablename, 
        indexes = c("patid", "obsdate")
      )
    
    assign(raw_tablename, data)
  }
}


############################################################################################

# Clean medcodes then merge with index dates
# Remove medcodes before DOB or after lcd/deregistration

analysis = cprd$analysis("all")

diabetes_cohort <- diabetes_cohort %>% analysis$cached("diabetes_cohort")

index_dates <- diabetes_cohort %>%
  filter(!is.na(dm_diag_date)) %>%
  select(patid, index_date=dm_diag_date)


# Clean deficit data and combine with index dates
analysis <- cprd$analysis("at_diag")

for (deficit in efi_deficits) {
  
  print(paste("merging index dates with", deficit, "code occurrences"))
  
  # Shorten deficit name
  deficit <- get_short_deficit(deficit)
  
  # Define table names
  medcode_tablename <- paste0("raw_", deficit, "_medcodes")
  index_date_merge_tablename <- paste0("full_", deficit, "_diag_merge")
  
  # If the table exists
  if (exists(medcode_tablename)) {
    
    # Select relevant columns from the raw medcode table
    medcodes <- get(medcode_tablename) %>%
      select(patid, date = obsdate, code = medcodeid)
  }
  
  # Clean data by joining valid date info
  medcodes_clean <- medcodes %>%
    inner_join(cprd$tables$validDateLookup, by = "patid") %>%
    filter(date >= min_dob & date <= gp_end_date) %>%
    select(patid, date, code)
  
  rm(medcodes)
  
  # Merge with diagnosis date info
  data <- medcodes_clean %>%
    inner_join(index_dates, by="patid") %>%
    mutate(datediff = datediff(date, index_date)) %>%
    analysis$cached(
      index_date_merge_tablename,
      index = "patid")
  
  rm(medcodes_clean)
  
  assign(index_date_merge_tablename, data)
  
  rm(data)
}


############################################################################################

# Find if there has been any instance of pre-index date occurrence of deficit

# Initialise efi table
efi <- index_dates


for (deficit in efi_deficits) {
  
  print(paste("Working out pre-index date code occurrences for", deficit))
  
  # Shorten deficit name
  deficit <- get_short_deficit(deficit)
  
  # Define table and column names
  index_date_merge_tablename <- paste0("full_", deficit, "_diag_merge")
  interim_efi_table <- paste0("efi_interim_", deficit)
  pre_index_date_indicator <- paste0("pre_index_date_", deficit)
  pre_index_date_earliest_date_variable <- paste0("pre_index_date_earliest_", deficit)
  
  # Get earliest date of pre-diagnosis occurrence
  pre_index_date <- get(index_date_merge_tablename) %>%
    filter(date <= index_date) %>%
    group_by(patid) %>%
    summarise(
      !!pre_index_date_earliest_date_variable := min(date, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    ungroup()
  
  # Convert the earliest date variable to a symbol
  pre_index_date_earliest_date_variable  <- sym(pre_index_date_earliest_date_variable)
  
  # Merge pre-index date data into the eFI table and create a boolean indicator (1 if 
  # there was ever an occurrence of this deficit on or before diagnosis)
  efi <- efi %>%
    left_join(pre_index_date, by = "patid") %>%
    mutate(
      !!pre_index_date_indicator := !is.na(!!pre_index_date_earliest_date_variable )
    ) %>%
    analysis$cached(
      interim_efi_table,
      unique_indexes = "patid")
}


# Drop all 'pre_index_date_earliest_*' columns from the final 'efi' table for now
efi <- efi %>%
  select(-matches("^pre_index_date_earliest_"))

# Set diabetes and polypharmacy to 1
efi <- efi %>%
  mutate(pre_index_date_efi_diabetes = 1L,
         pre_index_date_efi_polypharmacy = 1L) %>%
  analysis$cached(
    "efi_deficits",
    unique_indexes = "patid"
  )


# Sum deficits and calculate score

efi_deficits_short <- lapply(efi_deficits, get_short_deficit)
deficit_vars <- paste0("pre_index_date_", efi_deficits_short)

sql_adding_expr <- paste(deficit_vars, collapse = " + ")

efi <- efi %>%
  mutate(efi_n_deficits=dbplyr::sql(sql_adding_expr),
         pre_index_date_efi_score = efi_n_deficits / 36,
         pre_index_date_efi_cat = case_when(
           pre_index_date_efi_score < 0.12 ~ "fit",
           pre_index_date_efi_score >= 0.12 & pre_index_date_efi_score < 0.24 ~ "mild",
           pre_index_date_efi_score >= 0.24 & pre_index_date_efi_score < 0.36 ~ "moderate",
           pre_index_date_efi_score >=0.36 ~ "severe" )) %>%
  analysis$cached(
    "efi",
    unique_indexes = "patid")
