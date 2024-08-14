
# Extracts dates for alcohol consumption code occurrences in GP records

# Merges with drug start and stop dates

# Defines alcohol status at drug start according to our algorithm, described here: https://github.com/Exeter-Diabetes/CPRD-Codelists#alcohol-consumption


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("pedro_BP")


############################################################################################

# Pull out all raw code instances and cache with 'all_patid' prefix

analysis = cprd$analysis("all_patid")

# Clean: remove if before DOB or after lcd/deregistration/death, and re-cache

clean_alcohol_medcodes <- clean_alcohol_medcodes %>%
  analysis$cached("clean_alcohol_medcodes", indexes=c("patid", "date", "alcohol_cat"))


############################################################################################

# Find alcohol status according to algorithm at drug start dates

# Get drug start dates
analysis = cprd$analysis("pedro_BP")
drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")

# Join with alcohol codes on patid and retain codes before drug start date or up to 7 days after
predrug_alcohol_codes <- drug_start_stop %>%
  # select important variables
  select(patid, dstartdate, drugclass, druginstance) %>%
  # combine drug starts with alcohol
  inner_join(clean_alcohol_medcodes, by="patid") %>%
  # keep only values before 7 days after treatment initiation
  filter(datediff(date, dstartdate)<=7) %>%
  # cache this table
  analysis$cached("predrug_alcohol_merge", indexes=c("patid", "dstartdate", "drugclass", "alcohol_cat"))

## Find if ever previously a 'harmful' drinker (category 3)
harmful_drinker_ever <- predrug_alcohol_codes %>%
  # keep only level 3 alcohol category
  filter(alcohol_cat=="AlcoholConsumptionLevel3") %>%
  # keep only unique entries
  distinct(patid, dstartdate, drugclass) %>%
  # create variable
  mutate(harmful_drinker_ever=1L)

## Find most recent code
### If different categories on same day, use highest
most_recent_code <- predrug_alcohol_codes %>%
  # keep only unique entries
  distinct(patid, dstartdate, drugclass, date, alcohol_cat) %>%
  # create variable
  mutate(alcohol_cat_numeric = ifelse(alcohol_cat=="AlcoholConsumptionLevel0", 0L,
                                      ifelse(alcohol_cat=="AlcoholConsumptionLevel1", 1L,
                                             ifelse(alcohol_cat=="AlcoholConsumptionLevel2", 2L,
                                                    ifelse(alcohol_cat=="AlcoholConsumptionLevel3", 3L, NA))))) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # keep only most recent entry
  filter(date==max(date, na.rm=TRUE)) %>%
  # keep max category
  filter(alcohol_cat_numeric==max(alcohol_cat_numeric, na.rm=TRUE)) %>%
  # remove grouping
  ungroup() %>%
  # drop column
  select(-date) %>%
  # cache this table
  analysis$cached("alcohol_interim", indexes=c("patid", "dstartdate", "drugclass"))

## Pull together
alcohol_cat <- drug_start_stop %>%
  # keep only unique entries
  distinct(patid, dstartdate, drugclass, druginstance) %>%
  # combine drug starts with alcohol tables
  left_join(harmful_drinker_ever, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(most_recent_code, by = c("patid", "dstartdate", "drugclass")) %>%
  # create variables
  mutate(alcohol_cat_numeric=ifelse(!is.na(harmful_drinker_ever) & harmful_drinker_ever==1, 3L, alcohol_cat_numeric),
         
         alcohol_cat=case_when(
           alcohol_cat_numeric==0 ~ "None",
           alcohol_cat_numeric==1 ~ "Within limits",
           alcohol_cat_numeric==2 ~ "Excess",
           alcohol_cat_numeric==3 ~ "Harmful"
         )) %>%
  # select important variables
  select(-c(alcohol_cat_numeric, harmful_drinker_ever)) %>%
  # cache this table
  analysis$cached("alcohol",indexes= c("patid", "dstartdate", "drugclass"))



