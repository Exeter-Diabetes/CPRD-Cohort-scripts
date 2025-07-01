
# Extracts dates for comorbidity code occurrences in GP and HES records

# Merges with drug start and stop dates

# Then finds earliest predrug, latest predrug, and earliest postdrug occurrence for each comorbidity

# Plus binary 'is there a predrug occurrence?' variables

# Also find binary yes/no whether they had hospital admission in previous year to drug start, and when first postdrug hospital admission was for any cause, and what this cause is (ICD-10 code)

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

# Define comorbidities
## If you add comorbidity to the end of this list, code should run fine to incorporate new comorbidity, as long as you delete final 'mm_comorbidities' table

# Codelists we also have which haven't been updated: bipolar_disorder, care_home, deep_vein_thrombosis, diabetes_remission, fluvacc_stopflu_med, haemochromatosis_spocc, hearing_loss, language, learning_disability, nhshealthcheck, pancreatic_exocrine_insufficiency, pancreaticcancer_spocc, pneumococcal_vaccine_med, positive_covid_tests, pulmonary_embolism, schizophrenia, sev_mental_illness, surgicalpancreaticresection. Haven't included flu vaccines (STOPflu codelist).


comorbids <- c("af",
               "angina",
               "anxiety_disorders",
               "asthma",
               "benignprostatehyperplasia",
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
               "volume_depletion",
               "genital_infection",
               "genital_infection_nonspec"
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
      inner_join(codes[[paste0("opcs4_",i)]], sql_on="LHS.OPCS LIKE CONCAT(opcs4,'%')") %>%
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

# Clean and combine medcodes, ICD10 codes and OPCS4 codes, then merge with drug start dates
## Remove medcodes and HES codes before DOB or after lcd/deregistration
## No need to remove HES codes after end of HES records as no dates later than 31/03/2023 in records
## NB: for biomarkers, cleaning and combining with drug start dates is 2 separate steps with caching between, but as there are fewer cleaning steps for comorbidities I have made this one step here


# Get drug start dates

analysis = cprd$analysis("mm")

drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")


# Clean comorbidity data and combine with drug start dates

for (i in comorbids) {
  
  print(paste("merging drug dates with", i, "code occurrences"))
  
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  
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
      mutate(source="hes_icd10")

  }
    
  if (exists(opcs4_tablename)) {
    
    opcs4_codes <- get(opcs4_tablename) %>%
      select(patid, date=evdate, code=OPCS) %>%
      mutate(source="hes_opcs4")
    
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
    filter(date>=min_dob & date<=gp_end_date) %>%
    select(patid, date, source, code)
  
  rm(all_codes)
  
  data <- all_codes_clean %>%
    inner_join((drug_start_stop %>% select(patid, dstartdate, drug_class, drug_substance, drug_instance)), by="patid") %>%
    mutate(drugdatediff=datediff(date, dstartdate)) %>%
    analysis$cached(drug_merge_tablename, indexes=c("patid", "dstartdate", "drug_class", "drug_substance"))
  
  rm(all_codes_clean)
  
  assign(drug_merge_tablename, data)
  
  rm(data)

}
  

############################################################################################

# Find earliest predrug, latest predrug and first postdrug dates
## Leave genital_infection_non_spec, amputation and family history of diabetes for now as need to be processed differently

comorbids <- setdiff(comorbids, c("genital_infection_nonspec", "hosp_cause_majoramputation", "hosp_cause_minoramputation", "fh_diabetes_positive", "fh_diabetes_negative"))

comorbidities <- drug_start_stop %>%
  select(patid, dstartdate, drug_class, drug_substance, drug_instance)


for (i in comorbids) {
  
  print(paste("working out predrug and postdrug code occurrences for", i))
  
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  interim_comorbidity_table <- paste0("comorbidities_interim_", i)
  predrug_earliest_date_variable <- paste0("predrug_earliest_", i)
  predrug_latest_date_variable <- paste0("predrug_latest_", i)
  predrug_variable <- paste0("predrug_", i)
  postdrug_date_variable <- paste0("postdrug_first_", i)
  
  predrug <- get(drug_merge_tablename) %>%
    filter(date<=dstartdate) %>%
    group_by(patid, dstartdate, drug_substance) %>%
    summarise({{predrug_earliest_date_variable}}:=min(date, na.rm=TRUE),
              {{predrug_latest_date_variable}}:=max(date, na.rm=TRUE)) %>%
    ungroup()
  
  postdrug <- get(drug_merge_tablename) %>%
    filter(date>dstartdate) %>%
    group_by(patid, dstartdate, drug_substance) %>%
    summarise({{postdrug_date_variable}}:=min(date, na.rm=TRUE)) %>%
    ungroup()
  
  predrug_earliest_date_variable <- as.symbol(predrug_earliest_date_variable)
  
  comorbidities <- comorbidities %>%
    left_join(predrug, by=c("patid", "dstartdate", "drug_substance")) %>%
    left_join(postdrug, by=c("patid", "dstartdate", "drug_substance")) %>%
    mutate({{predrug_variable}}:=!is.na(predrug_earliest_date_variable)) %>%
    analysis$cached(interim_comorbidity_table, indexes=c("patid", "dstartdate", "drug_substance"))
}


############################################################################################

# Make separate tables for genital infection, amputation and fh_diabetes as need to combine 2 x amputation codes / combine positive and negative fh_diabetes codes first

drug_start_stop <- drug_start_stop %>%
  select(patid, dstartdate, drug_substance)

## Unspecific GI variable - have to have genital_infection_non_spec medcode and topical_candidal_meds prodcode on same day

topical_candidal_meds <- topical_candidal_meds %>% analysis$cached("full_topical_candidal_meds_drug_merge")

unspecific_gi <- full_genital_infection_nonspec_drug_merge %>%
  inner_join((topical_candidal_meds %>% select(patid, topical_candidal_meds_date=date)), by="patid") %>%
  filter(date==topical_candidal_meds_date) %>%
  select(-topical_candidal_meds_date)

predrug_unspecific_gi <- unspecific_gi %>%
  filter(date<=dstartdate) %>%
  group_by(patid, dstartdate, drug_substance) %>%
  summarise(predrug_earliest_unspecific_gi=min(date, na.rm=TRUE),
            predrug_latest_unspecific_gi=max(date, na.rm=TRUE)) %>%
  ungroup()

postdrug_unspecific_gi <- unspecific_gi %>%
  filter(date>dstartdate) %>%
  group_by(patid, dstartdate, drug_substance) %>%
  summarise(postdrug_first_unspecific_gi=min(date, na.rm=TRUE)) %>%
  ungroup()

unspecific_gi <- drug_start_stop %>%
  left_join(predrug_unspecific_gi, by=c("patid", "dstartdate", "drug_substance")) %>%
  left_join(postdrug_unspecific_gi, by=c("patid", "dstartdate", "drug_substance")) %>%
  mutate(predrug_unspecific_gi=!is.na(predrug_earliest_unspecific_gi)) %>%
  analysis$cached("comorbidities_interim_unspecific_gi", indexes=c("patid", "dstartdate", "drug_substance"))


## Amputation variable - use earliest of hosp_cause_majoramputation and hosp_cause_minoramputation

amputation <- full_hosp_cause_majoramputation_drug_merge %>% union_all(full_hosp_cause_minoramputation_drug_merge)

predrug_amputation <- amputation %>%
  filter(date<=dstartdate) %>%
  group_by(patid, dstartdate, drug_substance) %>%
  summarise(predrug_earliest_amputation=min(date, na.rm=TRUE),
            predrug_latest_amputation=max(date, na.rm=TRUE)) %>%
  ungroup()

postdrug_amputation <- amputation %>%
  filter(date>dstartdate) %>%
  group_by(patid, dstartdate, drug_substance) %>%
  summarise(postdrug_first_amputation=min(date, na.rm=TRUE)) %>%
  ungroup()

amputation_outcome <- drug_start_stop %>%
  left_join(predrug_amputation, by=c("patid", "dstartdate", "drug_substance")) %>%
  left_join(postdrug_amputation, by=c("patid", "dstartdate", "drug_substance")) %>%
  mutate(predrug_amputation=!is.na(predrug_earliest_amputation)) %>%
  analysis$cached("comorbidities_interim_amputation_outcome", indexes=c("patid", "dstartdate", "drug_substance"))


## Family history of diabetes - binary variable or missing

fh_diabetes_positive_latest <- full_fh_diabetes_positive_drug_merge %>%
  filter(date<=dstartdate) %>%
  group_by(patid, dstartdate, drug_substance) %>%
  summarise(fh_diabetes_positive_latest=max(date, na.rm=TRUE)) %>%
  ungroup()

fh_diabetes_negative_latest <- full_fh_diabetes_negative_drug_merge %>%
  filter(date<=dstartdate) %>%
  group_by(patid, dstartdate, drug_substance) %>%
  summarise(fh_diabetes_negative_latest=max(date, na.rm=TRUE)) %>%
  ungroup()

fh_diabetes <- drug_start_stop %>%
  left_join(fh_diabetes_positive_latest, by=c("patid", "dstartdate", "drug_substance")) %>%
  left_join(fh_diabetes_negative_latest, by=c("patid", "dstartdate", "drug_substance")) %>%
  mutate(fh_diabetes=ifelse(!is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest) & fh_diabetes_positive_latest==fh_diabetes_negative_latest, NA,
                            ifelse(!is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest) & fh_diabetes_positive_latest>fh_diabetes_negative_latest, 1L,
                                   ifelse(!is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest) & fh_diabetes_positive_latest<fh_diabetes_negative_latest, 0L,
                                          ifelse(!is.na(fh_diabetes_positive_latest) & is.na(fh_diabetes_negative_latest), 1L,
                                                 ifelse(is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest), 0L, NA)))))) %>%
  select(patid, dstartdate, drug_substance, fh_diabetes) %>%
  analysis$cached("comorbidities_interim_fh_diabetes", indexes=c("patid", "dstartdate", "drug_substance"))


############################################################################################

# Make separate table for whether hospital admission in previous year to drug start, and with first postdrug emergency hospitalisation for any cause, and what this cause is
## Admimeth never missing in hesHospital

hosp_admi_prev_year <- drug_start_stop %>%
  inner_join(cprd$tables$hesPrimaryDiagHosp, by="patid") %>%
  filter(!is.na(admidate) & datediff(dstartdate, admidate)<365 & datediff(dstartdate, admidate)>0) %>%
  distinct(patid, dstartdate, drug_substance) %>%
  mutate(hosp_admission_prev_year=1L)

hosp_admi_prev_year_count <- drug_start_stop %>%
  inner_join(cprd$tables$hesPrimaryDiagHosp, by="patid") %>%
  filter(!is.na(admidate) & datediff(dstartdate, admidate)<365 & datediff(dstartdate, admidate)>0) %>%
  group_by(patid, dstartdate, drug_substance) %>%
  summarise(hosp_admission_prev_year_count=n()) %>%
  ungroup()

# Can have multiple episodes and multiple spells starting on same date - need first episode of first spell
next_hosp_admi <- drug_start_stop %>%
  inner_join(cprd$tables$hesHospital, by="patid") %>%
  filter(!is.na(admidate) & admidate>dstartdate & admimeth!="11" & admimeth!="12" & admimeth!="13") %>%
  group_by(patid, dstartdate, drug_substance) %>%
  mutate(earliest_spell=min(spno, na.rm=TRUE)) %>% #have confirmed that lower spell number = earlier spell
  filter(spno==earliest_spell) %>%
  ungroup() %>%
  inner_join(cprd$tables$hesEpisodes, by=c("patid", "spno")) %>%
  filter(eorder==1) %>% #for episode, use episode order number to identify epikey of earliest episode within spell
  inner_join(cprd$tables$hesDiagnosisEpi, by=c("patid", "epikey")) %>%
  filter(d_order==1) %>%
  select(patid, dstartdate, drug_substance, postdrug_first_emergency_hosp=epistart.x, postdrug_first_emergency_hosp_cause=ICD)


hosp_admi <- drug_start_stop %>%
  left_join(hosp_admi_prev_year, by=c("patid", "dstartdate", "drug_substance")) %>%
  left_join(hosp_admi_prev_year_count, by=c("patid", "dstartdate", "drug_substance")) %>%
  left_join(next_hosp_admi, by=c("patid", "dstartdate", "drug_substance")) %>%
  analysis$cached("comorbidities_interim_hosp_admi", indexes=c("patid", "dstartdate", "drug_substance"))


############################################################################################

# Join together interim_comorbidity_table with unspecific_gi, amputation, family history of diabetes and hospital admission tables
### Also rename genital_infection to medspecific_gi

comorbidities <- comorbidities %>%
  left_join(unspecific_gi, by=c("patid", "dstartdate", "drug_substance")) %>%
  rename(predrug_earliest_medspecific_gi=predrug_earliest_genital_infection,
         predrug_latest_medspecific_gi=predrug_latest_genital_infection,
         postdrug_first_medspecific_gi=postdrug_first_genital_infection,
         predrug_medspecific_gi=predrug_genital_infection) %>%
  left_join(amputation_outcome, by=c("patid", "dstartdate", "drug_substance")) %>%
  left_join(fh_diabetes, by=c("patid", "dstartdate", "drug_substance")) %>%
  left_join(hosp_admi, by=c("patid", "dstartdate", "drug_substance")) %>%
  analysis$cached("comorbidities", indexes=c("patid", "dstartdate", "drug_substance"))

