
# Extracts dates for comorbidity code occurrences in GP and HES records

# Merges with index dates (diagnosis dates)

# Then finds earliest and latest pre-index date occurrence, and earliest post-index date occurrence for each comorbidity

# Plus binary 'is there a pre-index date occurrence?' variables


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

# Define comorbidities
## If you add comorbidity to the end of this list, code should run fine to incorporate new comorbidity, as long as you delete final 'comorbidities' table

comorbids <- c("af",
               "angina",
               "anxiety_disorders",
               "asthma",
               "bph",
               "bronchiectasis",
               "ckd5_code",
               "cld",
               "copd",
               "cysticfibrosis",
               "dementia",
               "diabeticnephropathy",
               "dka",
               "falls",
               "fh_diabetes", #note includes sibling, child, parents
               "fh_premature_cvd", #family history of premature CVD - for QRISK2
               "frailty_simple",
               "haem_cancer",
               "heartfailure",
               "hosp_cause_majoramputation",
               "hosp_cause_minoramputation",
               "hypertension",
               "ihd", #ischaemic heart disease
               "incident_mi",
               "incident_stroke",
               "lowerlimbfracture",
               "micturition_control",
               "myocardialinfarction",
               "neuropathy",
               "osteoporosis",
               "otherneuroconditions",
               "pad", #peripheral arterial disease
               "pulmonaryfibrosis",
               "pulmonaryhypertension",
               "retinopathy",
               "revasc", #revascularisation procedure
               "rheumatoidarthritis",
               "solid_cancer",
               "solidorgantransplant",
               "stroke",
               "tia",  #transient ischaemic attack
               "ukpds_photocoagulation",
               "unstableangina",
               "urinary_frequency",
               "vitreoushemorrhage",
               "volume_depletion"
)


############################################################################################

# Pull out all raw code instances and cache with 'all_patid' prefix
## Some of these already exist from previous analyses
## Don't want to include ICD10 codes for hypertension - previous note from Andy: "Hypertension is really a chronic condition and it should really be diagnosed in primary care. I would be suspicious of the diagnosis in people with only a HES code. Might be one to look at in future and see if it triangulates with treatment (but a very low priority item I would say) - trust the GPs on hypertension."
## Can also decide whether only want primary reasons for hospitalisation (d_order=1) for ICD10 codes - see bottom of this section

analysis = cprd$analysis("all_patid")


for (i in comorbids) {
  
  if (length(codes[[i]]) > 0) {
    print(paste("making", i, "medcode table"))
    
    raw_tablename <- paste0("raw_", i, "_medcodes")
    
    data <- cprd$tables$observation %>%
      inner_join(codes[[i]], by="medcodeid") %>%
      analysis$cached(raw_tablename, indexes=c("patid", "obsdate"))
    
    assign(raw_tablename, data)

  }
  
  if (length(codes[[paste0("icd10_", i)]]) > 0 & i!="hypertension") {
    print(paste("making", i, "ICD10 code table"))
    
    raw_tablename <- paste0("raw_", i, "_icd10")
    
    data <- cprd$tables$hesDiagnosisEpi %>%
      inner_join(codes[[paste0("icd10_",i)]], sql_on="LHS.ICD LIKE CONCAT(icd10,'%')") %>%
      analysis$cached(raw_tablename, indexes=c("patid", "epistart"))
    
    assign(raw_tablename, data)
    
  }
  
  if (length(codes[[paste0("opcs4_", i)]]) > 0) {
    print(paste("making", i, "OPCS4 code table"))
    
    raw_tablename <- paste0("raw_", i, "_opcs4")
    
    data <- cprd$tables$hesProceduresEpi %>%
      inner_join(codes[[paste0("opcs4_",i)]],by=c("OPCS"="opcs4")) %>%
      analysis$cached(raw_tablename, indexes=c("patid", "evdate"))
      
      assign(raw_tablename, data)
    
  }
  
}


# Make new primary cause hospitalisation for heart failure, incident MI, and incident stroke comorbidities

raw_primary_hhf_icd10 <- raw_heartfailure_icd10 %>%
  filter(d_order==1) %>%
  analysis$cached("raw_primary_hhf_icd10", indexes=c("patid", "epistart"))

raw_primary_incident_mi_icd10 <- raw_incident_mi_icd10 %>%
  filter(d_order==1) %>%
  analysis$cached("raw_primary_incident_mi_icd10", indexes=c("patid", "epistart"))

raw_primary_incident_stroke_icd10 <- raw_incident_stroke_icd10 %>%
  filter(d_order==1) %>%
  analysis$cached("raw_primary_incident_stroke_icd10", indexes=c("patid", "epistart"))


## Add to beginning of list so don't have to remake interim tables when add new comorbidity to end of above list
comorbids <- c("primary_hhf", "primary_incident_mi", "primary_incident_stroke", comorbids)


# Separate frailty by severity into three different categories
## Add to beginning of list so don't have to remake tables when add new comorbidity to end of above list
raw_frailty_mild_medcodes <- raw_frailty_simple_medcodes %>% filter(frailty_simple_cat=="Mild")
raw_frailty_moderate_medcodes <- raw_frailty_simple_medcodes %>% filter(frailty_simple_cat=="Moderate")
raw_frailty_severe_medcodes <- raw_frailty_simple_medcodes %>% filter(frailty_simple_cat=="Severe")
comorbids <- setdiff(comorbids, "frailty_simple")
comorbids <- c("frailty_mild", "frailty_moderate", "frailty_severe", comorbids)


# Separate family history by whether positive or negative
## Add to beginning of list so don't have to remake tables when add new comorbidity to end of above list
raw_fh_diabetes_positive_medcodes <- raw_fh_diabetes_medcodes %>% filter(fh_diabetes_cat!="negative")
raw_fh_diabetes_negative_medcodes <- raw_fh_diabetes_medcodes %>% filter(fh_diabetes_cat=="negative")
comorbids <- setdiff(comorbids, "fh_diabetes")
comorbids <- c("fh_diabetes_positive", "fh_diabetes_negative", comorbids)


############################################################################################

# Clean and combine medcodes, ICD10 codes and OPCS4 codes, then merge with index date
## Remove medcodes before DOB or after lcd/deregistration/death
## Remove HES codes before DOB or after 31/10/2020 (latest date in HES records) or death
## NB: for baseline_biomarkers, cleaning and combining with index date is 2 separate steps, but as there are fewer cleaning steps for comorbidities I have made this one step here


## Get index dates (diagnosis dates)

analysis = cprd$analysis("all")

diabetes_cohort <- diabetes_cohort %>% analysis$cached("diabetes_cohort")

index_dates <- diabetes_cohort %>%
  filter(!is.na(dm_diag_date)) %>%
  select(patid, index_date=dm_diag_date)


## Clean comorbidity data and combine with index 

analysis = cprd$analysis("at_diag")

for (i in comorbids) {
  
  print(paste("merging index dates with", i, "code occurrences"))
  
  index_date_merge_tablename <- paste0("full_", i, "_index_date_merge")
  
  medcode_tablename <- paste0("raw_", i, "_medcodes")
  icd10_tablename <- paste0("raw_", i, "_icd10")
  opcs4_tablename <- paste0("raw_", i, "_opcs4")
  

  if (exists(medcode_tablename)) {
    
    medcodes <- get(medcode_tablename) %>%
      select(patid, date=obsdate, code=medcodeid) %>%
      mutate(source="gp")
    
  }
  
  if (exists(icd10_tablename)) {
    
    icd10_codes <- get(icd10_tablename) %>%
      select(patid, date=epistart, code=ICD) %>%
      mutate(source="hes")

  }
    
  if (exists(opcs4_tablename)) {
    
    opcs4_codes <- get(opcs4_tablename) %>%
      select(patid, date=evdate, code=OPCS) %>%
      mutate(source="hes")
    
  }
  
  
  if (exists("medcodes")) {
    
    all_codes <- medcodes
    rm(medcodes)
    
    if(exists("icd10_codes")) {
      all_codes <- all_codes %>%
        union_all(icd10_codes)
      rm(icd10_codes)
    }
    
    if(exists("opcs4_codes")) {
      all_codes <- all_codes %>%
        union_all(opcs4_codes)
      rm(opcs4_codes)
    }
  }
  
  else if (exists("icd10_codes")) {
    
    all_codes <- icd10_codes
    rm(icd10_codes)
    
    if(exists("opcs4_codes")) {
      all_codes <- all_codes %>%
        union_all(opcs4_codes)
      rm(opcs4_codes)
    }
  }
  
  else if(exists("opcs4_codes")) {
    
    all_codes <- opcs4_codes
    rm(opcs4_codes)
  }

  all_codes_clean <- all_codes %>%
    inner_join(cprd$tables$validDateLookup, by="patid") %>%
    filter(date>=min_dob & ((source=="gp" & date<=gp_end_date) | (source=="hes" & date<=as.Date("2023-03-31")))) %>%
    select(patid, date, source, code)
  
  rm(all_codes)
  
  data <- all_codes_clean %>%
    inner_join(index_dates, by="patid") %>%
    mutate(datediff=datediff(date, index_date)) %>%
    analysis$cached(index_date_merge_tablename, index="patid")
  
  rm(all_codes_clean)
  
  assign(index_date_merge_tablename, data)
  
  rm(data)

}
  

############################################################################################

# Find earliest pre-index date, latest pre-index date and first post-index date dates
## Leave amputation and family history of diabetes for now as need to be processed differently

comorbids <- setdiff(comorbids, c("hosp_cause_majoramputation", "hosp_cause_minoramputation", "fh_diabetes_positive", "fh_diabetes_negative"))

comorbidities <- index_dates

for (i in comorbids) {
  
  print(paste("working out pre- and post-index date code occurrences for", i))
  
  index_date_merge_tablename <- paste0("full_", i, "_index_date_merge")
  interim_comorbidity_table <- paste0("comorbidities_interim_", i)
  pre_index_date_earliest_date_variable <- paste0("pre_index_date_earliest_", i)
  pre_index_date_latest_date_variable <- paste0("pre_index_date_latest_", i)
  pre_index_date_variable <- paste0("pre_index_date_", i)
  post_index_date_date_variable <- paste0("post_index_date_first_", i)
  
  pre_index_date <- get(index_date_merge_tablename) %>%
    filter(date<=index_date) %>%
    group_by(patid) %>%
    summarise({{pre_index_date_earliest_date_variable}}:=min(date, na.rm=TRUE),
              {{pre_index_date_latest_date_variable}}:=max(date, na.rm=TRUE)) %>%
    ungroup()
  
  post_index_date <- get(index_date_merge_tablename) %>%
    filter(date>index_date) %>%
    group_by(patid,) %>%
    summarise({{post_index_date_date_variable}}:=min(date, na.rm=TRUE)) %>%
    ungroup()
  
  pre_index_date_earliest_date_variable <- as.symbol(pre_index_date_earliest_date_variable)
  
  comorbidities <- comorbidities %>%
    left_join(pre_index_date, by="patid") %>%
    mutate({{pre_index_date_variable}}:=!is.na(pre_index_date_earliest_date_variable)) %>%
    left_join(post_index_date, by="patid") %>%
    analysis$cached(interim_comorbidity_table, unique_indexes="patid")
}


############################################################################################

# Make separate tables for amputation and fh_diabetes as need to combine 2 x amputation codes / combine positive and negative fh_diabetes codes first

## Amputation variable - use earliest of hosp_cause_majoramputation and hosp_cause_minoramputation

amputation <- full_hosp_cause_majoramputation_index_date_merge %>% union_all(full_hosp_cause_minoramputation_index_date_merge)

pre_index_date_amputation <- amputation %>%
  filter(date<=index_date) %>%
  group_by(patid) %>%
  summarise(pre_index_date_earliest_amputation=min(date, na.rm=TRUE),
            pre_index_date_latest_amputation=max(date, na.rm=TRUE)) %>%
  ungroup()

post_index_date_amputation <- amputation %>%
  filter(date>index_date) %>%
  group_by(patid) %>%
  summarise(post_index_date_first_amputation=min(date, na.rm=TRUE)) %>%
  ungroup()

amputation_outcome <- index_dates %>%
  left_join(pre_index_date_amputation, by="patid") %>%
  left_join(post_index_date_amputation, by="patid") %>%
  mutate(pre_index_date_amputation=!is.na(pre_index_date_earliest_amputation)) %>%
  analysis$cached("comorbidities_interim_amputation_outcome", unique_indexes="patid")


## Family history of diabetes - binary variable or missing

fh_diabetes_positive_latest <- full_fh_diabetes_positive_index_date_merge %>%
  filter(date<=index_date) %>%
  group_by(patid) %>%
  summarise(fh_diabetes_positive_latest=max(date, na.rm=TRUE)) %>%
  ungroup()

fh_diabetes_negative_latest <- full_fh_diabetes_negative_index_date_merge %>%
  filter(date<=index_date) %>%
  group_by(patid) %>%
  summarise(fh_diabetes_negative_latest=max(date, na.rm=TRUE)) %>%
  ungroup()

fh_diabetes <- index_dates %>%
  left_join(fh_diabetes_positive_latest, by="patid") %>%
  left_join(fh_diabetes_negative_latest, by="patid") %>%
  mutate(fh_diabetes=ifelse(!is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest) & fh_diabetes_positive_latest==fh_diabetes_negative_latest, NA,
                            ifelse(!is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest) & fh_diabetes_positive_latest>fh_diabetes_negative_latest, 1L,
                                   ifelse(!is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest) & fh_diabetes_positive_latest<fh_diabetes_negative_latest, 0L,
                                          ifelse(!is.na(fh_diabetes_positive_latest) & is.na(fh_diabetes_negative_latest), 1L,
                                                 ifelse(is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest), 0L, NA)))))) %>%
  select(patid, index_date, fh_diabetes) %>%
  analysis$cached("comorbidities_interim_fh_diabetes", unique_indexes="patid")

############################################################################################

# Join together interim_comorbidity_table with amputation, family history of diabetes and hospital admission tables

comorbidities <- comorbidities %>%
  left_join((amputation_outcome %>% select(-index_date)), by="patid") %>%
  left_join((fh_diabetes %>% select(-index_date)), by="patid") %>%
  analysis$cached("comorbidities", unique_indexes="patid")
