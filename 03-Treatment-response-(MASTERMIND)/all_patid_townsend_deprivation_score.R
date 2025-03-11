
# Produces all_patid_townsend_deprivation_score table

# Uses:
## IMD2019 decile
## IMD2019 decile-LSOA 2011 lookup from: https://www.gov.uk/government/statistics/english-indices-of-deprivation-2015 
## LSOA2011-TDS 2011 from: https://statistics.ukdataservice.ac.uk/dataset/2011-uk-townsend-deprivation-scores/resource/de580af3-6a9f-4795-b651-449ae16ac2be

# See: https://github.com/drkgyoung/Exeter_Diabetes_codelists/blob/main/readme.md#townsend-deprivation-scores


################################################################################################################################

##################### SETUP ####################################################################################################

library(aurum)
library(tidyverse)
library(readxl)

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024", cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("all_patid")


################################################################################################################################

##################### IMPORT IMD/TDS/LSOA LOOKUPS ##############################################################################

setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

imd_lsoa <- read_excel("Townsend lookups/File_1_-_IMD2019_Index_of_Multiple_Deprivation.xlsx", sheet="IMD2019") %>%
  select(lsoa_2011='LSOA code (2011)',
         imd_decile='Index of Multiple Deprivation (IMD) Decile')

townsend_lsoa <- read_csv("Townsend lookups/Scores- 2011 UK LSOA.csv") %>%
  select(lsoa_2011=GEO_CODE, tds_2011=TDS)


################################################################################################################################

##################### FIND MEDIAN TDS BY IMD DECILE ############################################################################

imd_townsend <- imd_lsoa %>%
  inner_join(townsend_lsoa, by="lsoa_2011") %>%
  select(-lsoa_2011) %>%
  group_by(imd_decile) %>%
  summarise(tds_2011=round(median(tds_2011), 3)) %>%
  ungroup()


################################################################################################################################

##################### MAKE MYSQL TABLE OF TOWNSEND SCORES ######################################################################


townsend_score <- cprd$tables$patientImd %>%
  select(patid, imd_decile) %>%
  inner_join(imd_townsend, by="imd_decile", copy=TRUE) %>%
  analysis$cached("townsend_score", unique_index="patid")

