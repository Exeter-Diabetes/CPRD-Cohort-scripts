
# Calculates electronic frailty index (https://pubmed.ncbi.nlm.nih.gov/26944937/) at drug start dates
# Polypharmacy assumed to be 1

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "01/06/2024")

analysis = cprd$analysis("mm")


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

# Clean medcodes then merge with drug start dates
# Remove medcodes before DOB or after lcd/deregistration


analysis <- cprd$analysis("mm")


drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")


# Clean deficit data and combine with drug start dates
for (deficit in efi_deficits) {
  
  print(paste("merging drug dates with", deficit, "code occurrences"))
  
  # Shorten deficit name
  deficit <- get_short_deficit(deficit)
  
  # Define table names
  medcode_tablename <- paste0("raw_", deficit, "_medcodes")
  drug_merge_tablename <- paste0("full_", deficit, "_merge")
  
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
  
  # Merge with drug start info
  data <- medcodes_clean %>%
    inner_join(
      drug_start_stop %>%
        select(patid, dstartdate, drug_class, drug_substance, drug_instance),
      by = "patid"
    ) %>%
    mutate(drugdatediff = datediff(date, dstartdate)) %>%
    analysis$cached(
      drug_merge_tablename,
      indexes = c("patid", "dstartdate", "drug_class", "drug_substance")
    )
  
  rm(medcodes_clean)
  
  assign(drug_merge_tablename, data)
  
  rm(data)
}

############################################################################################

# Find if there has been any instance of predrug occurrence of deficit

# Initialise efi table
efi <- drug_start_stop %>%
  select(patid, dstartdate, drug_class, drug_substance, drug_instance)


for (deficit in efi_deficits) {
  
  print(paste("Working out predrug code occurrences for", deficit))
  
  # Shorten deficit name
  deficit <- get_short_deficit(deficit)
  
  # Define table and column names
  drug_merge_tablename <- paste0("full_", deficit, "_merge")
  interim_efi_table <- paste0("efi_interim_", deficit)
  predrug_indicator <- paste0("predrug_", deficit)
  predrug_earliest_date_variable <- paste0("predrug_earliest_", deficit)
  
  # Get earliest date of predrug occurrence
  predrug <- get(drug_merge_tablename) %>%
    filter(date <= dstartdate) %>%
    group_by(patid, dstartdate, drug_substance) %>%
    summarise(
      !!predrug_earliest_date_variable := min(date, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    ungroup()
  
  # Convert the earliest date variable to a symbol
  predrug_earliest_date_variable  <- sym(predrug_earliest_date_variable)
  
  # Merge predrug data into the eFI table and create a boolean indicator (1 if 
  # there was ever an occurrence of this deficit on or before drug start date)
  efi <- efi %>%
    left_join(predrug, by = c("patid", "dstartdate", "drug_substance")) %>%
    mutate(
      !!predrug_indicator := !is.na(!!predrug_earliest_date_variable )
    ) %>%
    analysis$cached(
      interim_efi_table,
      indexes = c("patid", "dstartdate", "drug_substance")
    )
}


# Drop all 'predrug_earliest_*' columns from the final 'efi' table for now
efi <- efi %>%
  select(-matches("^predrug_earliest_"))


# - There are 203,198 patients that do not have a predrug_occurence of diabetes using the efi_diabetes codelist
#   These patients have records of diabetes medication in drug_start_stop and have record of diabetes using QOF codes
#   Fill all predrug_diabetes occurrences with 1
# - Fill all predrug_polypharmacy with 1 (assume every patient is on 5 or more medications for now).

efi <- efi %>%
  mutate(predrug_efi_diabetes = 1,
         predrug_efi_polypharmacy = 1) %>%
  analysis$cached(
    "efi_deficits",
    indexes = c("patid", "dstartdate", "drug_substance")
  )


# Sum deficits and calculate score

efi_deficits_short <- lapply(efi_deficits, get_short_deficit)
deficit_vars <- paste0("predrug_", efi_deficits_short)

sql_adding_expr <- paste(deficit_vars, collapse = " + ")

efi <- efi %>%
  mutate(efi_n_deficits=dbplyr::sql(sql_adding_expr),
         predrug_efi_score = efi_n_deficits / 36,
         predrug_efi_cat = case_when(
           predrug_efi_score < 0.12 ~ "fit",
           predrug_efi_score >= 0.12 & predrug_efi_score < 0.24 ~ "mild",
           predrug_efi_score >= 0.24 & predrug_efi_score < 0.36 ~ "moderate",
           predrug_efi_score >=0.36 ~ "severe" )) %>%
  analysis$cached(
    "efi",
    indexes = c("patid", "dstartdate", "drug_substance")
  )
