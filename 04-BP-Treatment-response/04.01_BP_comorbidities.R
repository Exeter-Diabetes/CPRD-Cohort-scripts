
# Extracts dates for comorbidity code occurrences in GP and HES records

# Merges with drug start and stop dates

# Then finds earliest predrug, latest predrug, and earliest postdrug occurrence for each comorbidity

# Plus binary 'is there a predrug occurrence?' variables

# Separate primary and secondary care diagnoses for postdrug occurrences for sensitivity analysis, as well as combined

# Also find binary yes/no whether they had hospital admission in previous year to drug start, and when first postdrug hospital admission was for any cause, and what this cause is (ICD-10 code)

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

# Define comorbidities
## If you add comorbidity to the end of this list, code should run fine to incorporate new comorbidity, as long as you delete final 'pedro_BP_comorbidities' table

comorbids <- c("af", #atrial fibrillation
               "angina",
               "asthma",
               "bronchiectasis",
               "ckd5_code",
               "cld",
               "copd",
               "cysticfibrosis",
               "dementia",
               "diabeticnephropathy",
               "fh_premature_cvd", #family history of premature CVD - for QRISK2
               "haem_cancer",
               "heartfailure",
               "hypertension",
               "ihd", #ischaemic heart disease
               "myocardialinfarction",
               "neuropathy",
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
               "anxiety_disorders",
               "genital_infection",
               "genital_infection_nonspec",
               "benignprostatehyperplasia",
               "micturition_control",
               "volume_depletion",
               "urinary_frequency",
               "falls",
               "lowerlimbfracture",
               "incident_mi",
               "incident_stroke",
               "fluvacc_stopflu_med",
               "dka",
               "hosp_cause_majoramputation",
               "hosp_cause_minoramputation",
               "osteoporosis",
               "unstableangina",
               "frailty_simple",
               "fh_diabetes" #note includes sibling, child, parents
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

raw_primary_incident_stroke_icd10 <- raw_incident_mi_icd10 %>%
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
## Remove medcodes before DOB or after lcd/deregistration/death
## Remove HES codes before DOB or after 31/10/2020 or death
## NB: for biomarkers, cleaning and combining with drug start dates is 2 separate steps with caching between, but as there are fewer cleaning steps for comorbidities I have made this one step here


# Get drug start dates

analysis = cprd$analysis("pedro_BP")

drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")


# Clean comorbidity data and combine with drug start dates

for (i in comorbids) {
  
  # print current comorbidity
  print(paste("merging drug dates with", i, "code occurrences"))
  
  # name of the table merge
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  
  # names for comorbidity codes
  medcode_tablename <- paste0("raw_", i, "_medcodes")
  icd10_tablename <- paste0("raw_", i, "_icd10")
  opcs4_tablename <- paste0("raw_", i, "_opcs4")
  
  # codes needed
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
  
  # If medcodes were created
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
    # If icd10 codes were created
  } else if (exists("icd10_codes")) {
    
    all_codes <- icd10_codes
    rm(icd10_codes)
    
    if(exists("opcs4_codes")) {
      all_codes <- all_codes %>%
        union_all(opcs4_codes)
      rm(opcs4_codes)
    }
    # If opcs4 codes were created
  } else if(exists("opcs4_codes")) {
    all_codes <- opcs4_codes
    rm(opcs4_codes)
  }
  
  all_codes_clean <- all_codes %>%
    # combine codes for each patient
    inner_join(cprd$tables$validDateLookup, by="patid") %>%
    # filter valid codes
    filter(date>=min_dob & ((source=="gp" & date<=gp_ons_end_date) | ((source=="hes_icd10" | source=="hes_opcs4") & (is.na(gp_ons_death_date) | date<=gp_ons_death_date)))) %>%
    # select important variables
    select(patid, date, source, code)
  
  # delete not needed table
  rm(all_codes)
  
  data <- all_codes_clean %>%
    # combine codes with drug starts
    inner_join((drug_start_stop %>% select(patid, dstartdate, drugclass, druginstance)), by="patid") %>%
    # create variable of difference between value and start of therapy
    mutate(drugdatediff=datediff(date, dstartdate)) %>%
    # cache this table
    analysis$cached(drug_merge_tablename, indexes=c("patid", "dstartdate", "drugclass"))
  
  # delete not needed table
  rm(all_codes_clean)
  # rename dataset
  assign(drug_merge_tablename, data)
  # delete not needed table
  rm(data)
  
}




############################################################################################

# Find earliest predrug, latest predrug and first postdrug dates
## Leave genital_infection_nonspec, fluvacc_stopflu_med, amputation and family history of diabetes for now as need to be processed differently

comorbids <- setdiff(comorbids, c("genital_infection_nonspec", "fluvacc_stopflu_med", "hosp_cause_majoramputation", "hosp_cause_minoramputation", "fh_diabetes_positive", "fh_diabetes_negative"))

comorbidities <- drug_start_stop %>%
  select(patid, dstartdate, drugclass, druginstance)


for (i in comorbids) {
  # current biomarker
  print(paste("working out predrug and postdrug code occurrences for", i))

  # name of table
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  interim_comorbidity_table <- paste0("comorbidities_interim_", i)
  # name of variable
  predrug_earliest_date_variable <- paste0("predrug_earliest_", i)
  predrug_latest_date_variable <- paste0("predrug_latest_", i)
  predrug_variable <- paste0("predrug_", i)
  postdrug_date_variable <- paste0("postdrug_first_", i)
  postdrug_gp_date_variable <- paste0("postdrug_first_", i, "_gp_only")
  postdrug_hes_icd10_date_variable <- paste0("postdrug_first_", i, "_hes_icd10_only")
  postdrug_hes_opcs4_date_variable <- paste0("postdrug_first_", i, "_hes_opcs4_only")

  # create pre drug comorbidity
  predrug <- get(drug_merge_tablename) %>%
    filter(date<=dstartdate) %>%
    group_by(patid, dstartdate, drugclass) %>%
    summarise({{predrug_earliest_date_variable}}:=min(date, na.rm=TRUE),
              {{predrug_latest_date_variable}}:=max(date, na.rm=TRUE)) %>%
    ungroup()

  # create post drug gp data comorbidity
  postdrug_gp <- get(drug_merge_tablename) %>%
    filter(date>dstartdate & source=="gp") %>%
    group_by(patid, dstartdate, drugclass) %>%
    summarise({{postdrug_gp_date_variable}}:=min(date, na.rm=TRUE)) %>%
    ungroup()
  
  # create post drug hes data comorbidity
  postdrug_hes_icd10 <- get(drug_merge_tablename) %>%
    filter(date>dstartdate & source=="hes_icd10") %>%
    group_by(patid, dstartdate, drugclass) %>%
    summarise({{postdrug_hes_icd10_date_variable}}:=min(date, na.rm=TRUE)) %>%
    ungroup()
  
  # create post drug opcs4 data comorbidity
  postdrug_hes_opcs4 <- get(drug_merge_tablename) %>%
    filter(date>dstartdate & source=="hes_opcs4") %>%
    group_by(patid, dstartdate, drugclass) %>%
    summarise({{postdrug_hes_opcs4_date_variable}}:=min(date, na.rm=TRUE)) %>%
    ungroup()
  
  # create post drug overall data comorbidity
  postdrug_overall <- get(drug_merge_tablename) %>%
    filter(date>dstartdate) %>%
    group_by(patid, dstartdate, drugclass) %>%
    summarise({{postdrug_date_variable}}:=min(date, na.rm=TRUE)) %>%
    ungroup()

  predrug_earliest_date_variable <- as.symbol(predrug_earliest_date_variable)

  # join comorbidities with tables
  comorbidities <- comorbidities %>%
    left_join(predrug, by=c("patid", "dstartdate", "drugclass")) %>%
    left_join(postdrug_hes_icd10, by=c("patid", "dstartdate", "drugclass")) %>%
    left_join(postdrug_hes_opcs4, by=c("patid", "dstartdate", "drugclass")) %>%
    left_join(postdrug_gp, by=c("patid", "dstartdate", "drugclass")) %>%
    left_join(postdrug_overall, by=c("patid", "dstartdate", "drugclass")) %>%
    # create variable with earliest date
    mutate({{predrug_variable}}:=!is.na(predrug_earliest_date_variable)) %>%
    # cache this table
    analysis$cached(interim_comorbidity_table, indexes=c("patid", "dstartdate", "drugclass"))
}


############################################################################################

# Make separate tables for genital_infection_nonspec, fluvacc_stopflu_med, amputation and fh_diabetes as need to be combined with definite_genital_infection_meds / fluvacc_stopflu_prod (prodcodes) / combine 2 x amputation medcodes / combine positive and negative fh_diabetes codes first (need to produce definite_genital_infection_meds / fluvacc_stopflu_prod full drug merge table in script 6_mm_non_diabetes_meds first)

drug_start_stop <- drug_start_stop %>%
  select(patid, dstartdate, drugclass)


## Unspecific GI variable - have to have medcode and prodcode on same day
### Also rename genital_infection to medspecific_gi

definite_gi_meds <- definite_gi_meds %>% analysis$cached("full_definite_genital_infection_meds_drug_merge")

unspecific_gi <- full_genital_infection_nonspec_drug_merge %>%
  # combine with medication tables
  inner_join((definite_gi_meds %>% select(patid, definite_gi_meds_date=date)), by="patid") %>%
  # keep only the correct date
  filter(date==definite_gi_meds_date) %>%
  # select important variable
  select(-definite_gi_meds_date)

predrug_unspecific_gi <- unspecific_gi %>%
  # keep only pre drug start
  filter(date<=dstartdate) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # find earliest and latest
  summarise(predrug_earliest_unspecific_gi=min(date, na.rm=TRUE),
            predrug_latest_unspecific_gi=max(date, na.rm=TRUE)) %>%
  # remove grouping
  ungroup()

postdrug_unspecific_gi <- unspecific_gi %>%
  # keep only post drug start
  filter(date>dstartdate) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # find earliest
  summarise(postdrug_first_unspecific_gi=min(date, na.rm=TRUE)) %>%
  # remove grouping
  ungroup()

unspecific_gi <- drug_start_stop %>%
  # combine tables
  left_join(predrug_unspecific_gi, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(postdrug_unspecific_gi, by=c("patid", "dstartdate", "drugclass")) %>%
  # create variable
  mutate(predrug_unspecific_gi=!is.na(predrug_earliest_unspecific_gi)) %>%
  # cache this table
  analysis$cached("comorbidities_interim_unspecific_gi", indexes=c("patid", "dstartdate", "drugclass"))



## Fluvacc_stopflu variable - use earliest of medcode and prodcode

fluvacc_stopflu_prod <- fluvacc_stopflu_prod %>% analysis$cached("full_fluvacc_stopflu_prod_drug_merge")

# combine tables
fluvacc <- full_fluvacc_stopflu_med_drug_merge %>% union_all(fluvacc_stopflu_prod)

predrug_fluvacc <- fluvacc %>%
  # keep only pre drug start date
  filter(date<=dstartdate) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # find earliest and latest
  summarise(predrug_earliest_fluvacc=min(date, na.rm=TRUE),
            predrug_latest_fluvacc=max(date, na.rm=TRUE)) %>%
  # remove grouping
  ungroup()

postdrug_fluvacc <- fluvacc %>%
  # keep only post drug start date
  filter(date>dstartdate) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # find earliest
  summarise(postdrug_first_fluvacc=min(date, na.rm=TRUE)) %>%
  # remove grouping
  ungroup()

flu_vaccination <- drug_start_stop %>%
  # combine tables
  left_join(predrug_fluvacc, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(postdrug_fluvacc, by=c("patid", "dstartdate", "drugclass")) %>%
  # create variable
  mutate(predrug_fluvacc=!is.na(predrug_earliest_fluvacc)) %>%
  # cache this table
  analysis$cached("comorbidities_interim_flu_vaccination", indexes=c("patid", "dstartdate", "drugclass"))



## Amputation variable - use earliest of hosp_cause_majoramputation and hosp_cause_minoramputation

amputation <- full_hosp_cause_majoramputation_drug_merge %>% union_all(full_hosp_cause_minoramputation_drug_merge)

predrug_amputation <- amputation %>%
  # keep only pre drug start date
  filter(date<=dstartdate) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # find earliest and latest
  summarise(predrug_earliest_amputation=min(date, na.rm=TRUE),
            predrug_latest_amputation=max(date, na.rm=TRUE)) %>%
  # remove grouping
  ungroup()

postdrug_amputation <- amputation %>%
  # keep only post drug start date
  filter(date>dstartdate) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # find earliest
  summarise(postdrug_first_amputation=min(date, na.rm=TRUE)) %>%
  # remove grouping
  ungroup()

amputation_outcome <- drug_start_stop %>%
  # combine tables
  left_join(predrug_amputation, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(postdrug_amputation, by=c("patid", "dstartdate", "drugclass")) %>%
  # create variable
  mutate(predrug_amputation=!is.na(predrug_earliest_amputation)) %>%
  # cache this table
  analysis$cached("comorbidities_interim_amputation_outcome", indexes=c("patid", "dstartdate", "drugclass"))


## Family history of diabetes - binary variable or missing

fh_diabetes_positive_latest <- full_fh_diabetes_positive_drug_merge %>%
  # keep only pre drug start date
  filter(date<=dstartdate) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # find earliest and latest
  summarise(fh_diabetes_positive_latest=max(date, na.rm=TRUE)) %>%
  # remove grouping
  ungroup()

fh_diabetes_negative_latest <- full_fh_diabetes_negative_drug_merge %>%
  # keep only post drug start date
  filter(date<=dstartdate) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # find earliest
  summarise(fh_diabetes_negative_latest=max(date, na.rm=TRUE)) %>%
  # remove grouping
  ungroup()

fh_diabetes <- drug_start_stop %>%
  # combine tables
  left_join(fh_diabetes_positive_latest, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(fh_diabetes_negative_latest, by=c("patid", "dstartdate", "drugclass")) %>%
  # create variable
  mutate(fh_diabetes=ifelse(!is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest) & fh_diabetes_positive_latest==fh_diabetes_negative_latest, NA,
                            ifelse(!is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest) & fh_diabetes_positive_latest>fh_diabetes_negative_latest, 1L,
                                   ifelse(!is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest) & fh_diabetes_positive_latest<fh_diabetes_negative_latest, 0L,
                                          ifelse(!is.na(fh_diabetes_positive_latest) & is.na(fh_diabetes_negative_latest), 1L,
                                                 ifelse(is.na(fh_diabetes_positive_latest) & !is.na(fh_diabetes_negative_latest), 0L, NA)))))) %>%
  # select important variables
  select(patid, dstartdate, drugclass, fh_diabetes) %>%
  # cache this table
  analysis$cached("comorbidities_interim_fh_diabetes", indexes=c("patid", "dstartdate", "drugclass"))




############################################################################################

# Make separate table for whether hospital admission in previous year to drug start, and with first postdrug emergency hospitalisation for any cause, and what this cause is
## Admimeth never missing in hesHospital

hosp_admi_prev_year <- drug_start_stop %>%
  # combine tables
  inner_join(cprd$tables$hesPrimaryDiagHosp, by="patid") %>%
  # keep only dates within 365 days of drug start
  filter(!is.na(admidate) & datediff(dstartdate, admidate)<365 & datediff(dstartdate, admidate)>0) %>%
  # keep only unique entries
  distinct(patid, dstartdate, drugclass) %>%
  # create variable
  mutate(hosp_admission_prev_year=1L)

hosp_admi_prev_year_count <- drug_start_stop %>%
  # combine tables
  inner_join(cprd$tables$hesPrimaryDiagHosp, by="patid") %>%
  # keep only dates within 365 days of drug start
  filter(!is.na(admidate) & datediff(dstartdate, admidate)<365 & datediff(dstartdate, admidate)>0) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # create variable
  summarise(hosp_admission_prev_year_count=n()) %>%
  # remove grouping
  ungroup()

# Can have multiple episodes and multiple spells starting on same date - need first episode of first spell
next_hosp_admi <- drug_start_stop %>%
  # combine tables
  inner_join(cprd$tables$hesHospital, by="patid") %>%
  # find episodes after drug start
  filter(!is.na(admidate) & admidate>dstartdate & admimeth!="11" & admimeth!="12" & admimeth!="13") %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # create variable
  mutate(earliest_spell=min(spno, na.rm=TRUE)) %>% #have confirmed that lower spell number = earlier spell
  # keep only first spell
  filter(spno==earliest_spell) %>%
  # remove grouping
  ungroup() %>%
  # combine tables
  inner_join(cprd$tables$hesEpisodes, by=c("patid", "spno")) %>%
  # keep only episode 1
  filter(eorder==1) %>% #for episode, use episode order number to identify epikey of earliest episode within spell
  # combine with tables
  inner_join(cprd$tables$hesDiagnosisEpi, by=c("patid", "epikey")) %>%
  # keep only first
  filter(d_order==1) %>%
  # select important variable
  select(patid, dstartdate, drugclass, postdrug_first_emergency_hosp=epistart.x, postdrug_first_emergency_hosp_cause=ICD)


hosp_admi <- drug_start_stop %>%
  # combine tables
  left_join(hosp_admi_prev_year, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(hosp_admi_prev_year_count, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(next_hosp_admi, by=c("patid", "dstartdate", "drugclass")) %>%
  # cache this table
  analysis$cached("comorbidities_interim_hosp_admi", indexes=c("patid", "dstartdate", "drugclass"))




############################################################################################

# Join together interim_comorbidity_table with genital infection, flu vaccination, amputation and hospital admission tables, and rename genital_infection variables to 'medspecific_gi'

comorbidities <- comorbidities %>%
  # combine tables
  left_join(unspecific_gi, by=c("patid", "dstartdate", "drugclass")) %>%
  # create variable
  rename(predrug_earliest_medspecific_gi=predrug_earliest_genital_infection,
         predrug_latest_medspecific_gi=predrug_latest_genital_infection,
         postdrug_first_medspecific_gi=postdrug_first_genital_infection,
         postdrug_first_medspecific_gi_gp_only=postdrug_first_genital_infection_gp_only,
         postdrug_first_medspecific_gi_hes_icd10_only=postdrug_first_genital_infection_hes_icd10_only,
         postdrug_first_medspecific_gi_hes_opcs4_only=postdrug_first_genital_infection_hes_opcs4_only,
         predrug_medspecific_gi=predrug_genital_infection) %>%
  # combine tables
  left_join(flu_vaccination, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(amputation_outcome, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(fh_diabetes, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(hosp_admi, by=c("patid", "dstartdate", "drugclass")) %>%
  # cache this table
  analysis$cached("comorbidities", indexes=c("patid", "dstartdate", "drugclass"))









