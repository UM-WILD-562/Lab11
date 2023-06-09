## ----setup, include=FALSE-------------------------------------------------------------------------------
knitr::opts_chunk$set(echo = TRUE)


## ----eval=TRUE, message=FALSE, results='hide'-----------------------------------------------------------

#function to install and load required packages
ipak <- function(pkg){
  new.pkg <- pkg[!(pkg %in% installed.packages()[, "Package"])]
  if (length(new.pkg)) 
    install.packages(new.pkg, dependencies = TRUE)
  sapply(pkg, require, character.only = TRUE)
}

packages <- c("tidyr","ggplot2","dplyr","stringr","lubridate","purrr","sf","terra","rgdal","maptools","readxl","amt","moveHMM","sjPlot","ggsci")

#run function to install packages
ipak(packages)


## -------------------------------------------------------------------------------------------------------
options(stringsAsFactors=FALSE)
crs.11 <- 26911         # EPSG:26911  UTM Zone 11 N, NAD 83
crs.latlong <- 4326     # EPSG:4326   LatLong
crs.sp.11 <- CRS("+proj=utm +zone=11 +ellps=GRS80 +datum=NAD83 +units=m")  # used by older sp package (which amt uses)


## -------------------------------------------------------------------------------------------------------
load('Data/Data 00 GPS Data.RData')
head(gps)
table(gps$species)
unique(gps$id)
ggplot(gps, aes(x, y, colour = species)) +geom_point()

## ----eval=FALSE-----------------------------------------------------------------------------------------
## ### Query out just some grizzly bear data from 1 season
## #table(gps$ID)
## #table(gps$season)
## #gpsGriz <- gps %>% filter(species == "grizzly bear")
## #gpsGriz2 <- gpsGriz %>%filter(season == "summer")
## #table(gpsGriz$species, gpsGriz$season)


## -------------------------------------------------------------------------------------------------------
gps.1 <- gps %>% mutate(ID = paste(species, id), .before = date.time) 
gps.1 <- gps.1 %>% mutate(Hour = hour(date.time.mst), Min = minute(date.time.mst)) %>% 
  mutate(Hour.d = Hour + (Min / 60)) %>% 
  mutate(hour.rad = Hour.d * 2 * pi /24) %>% 
  mutate(night.cos = cos(hour.rad)) %>% 
  dplyr::select(-c(Hour, Hour.d, hour.rad, Min))
head(gps.1)


## interpreting hours in radians
hour = hour(gps.1$date.time.mst)
min = minute(gps.1$date.time.mst)
hour.d = hour + (min/60)
hour.rad = hour.d * 2 * pi /24
night.cos = cos(hour.rad)
plot(night.cos, hour.d)
## so 0.0 = about 6 and 18 hour. -1 is noon, 1 is midnight.

## Add an index, i = 1... n for each ID within each species
gps.1 <- gps.1 %>%  arrange(species, ID, date.time) %>% 
  mutate(i = 1:n()) %>% 
  mutate(species = as.character(species), season = as.character(season))
head(gps.1)

## Create a dataframe (tibble) for each speciesXseason combination
df.species.season <- gps.1 %>% group_by(species, season) %>% 
  summarise() %>% 
  ungroup() %>% 
  mutate(xxx = 1:n(), .before = species)
n.data = nrow(df.species.season)
df.species.season

# link tibble with previous datset (gps.1) by speciesXseason combination
gps.2 <- inner_join(df.species.season, gps.1, by = c('species', 'season'))
head(gps.2)

data.list <- vector(mode = 'list', length = n.data)
move.list <- vector(mode = 'list', length = n.data)


## -------------------------------------------------------------------------------------------------------
data.list <- vector(mode = 'list', length = n.data)
move.list <- vector(mode = 'list', length = n.data)


## -------------------------------------------------------------------------------------------------------
for (j in 1:n.data){
  print(df.species.season[j,])
  tmp <- gps.2 %>% filter(xxx == j)
  tmp <- tmp %>% dplyr::select(i, ID, x, y, dt.min, night.cos) %>% 
    mutate(x = x/1000, y = y/1000) %>% 
    mutate(dt.min = ifelse(is.finite(dt.min), dt.min, 1000))
  tmp <- as.data.frame(tmp)
  tmp.move <- moveHMM::prepData(tmp, type="UTM") #, coordNames=c("x","y"))  # class moveData

 
  #plot(tmp.move, compact = TRUE)  # moveHMM::plot.moveData
  tmp.move$step = ifelse(is.finite(tmp.move$step) & tmp.move$step == 0, 0.001, tmp.move$step)
  tmp.move$step = ifelse(tmp.move$dt.min > 150, NA, tmp.move$step)                       # constrain model to two hour step lengths
  tmp.move$angle = ifelse(tmp.move$dt.min > 150, NA, tmp.move$angle)   
  
  #summary(as.data.frame(tmp.move))
  #hist(tmp.move$step)
  ## initial parameters for gamma and von Mises distributions
  mu0 <- c(0.1, 1) # step mean (two parameters: one for each state) in km
  sigma0 <- c(0.1, 1) # step SD
  zeromass0 <- c(0.1,0.05) # step zero-mass.   # for negative bionmial if have zero length steps
  stepPar0 <- c(mu0, sigma0) #,zeromass0)
  angleMean0 <- c(pi, 0) # angle mean
  kappa0 <- c(1,1) # angle concentration
  anglePar0 <- c(angleMean0, kappa0)
  ## call to fitting function
  m <- fitHMM(data=tmp.move, nbStates=2, stepPar0=stepPar0,  anglePar0=anglePar0, formula = ~ night.cos) 
  plotStationary(m, plotCI = TRUE)
  m
  state.p <- stateProbs(m)
  #head(state.p)
  tmp2 <- tmp %>% mutate(step = tmp.move$step, angle = tmp.move$angle, p1 = state.p[ ,1], p2 = state.p[ ,2]) %>% 
    dplyr::select(-dt.min, - night.cos, -x, -y)
  move.list[[j]] <- m
  data.list[[j]] <- tmp2
  
}


## -------------------------------------------------------------------------------------------------------
par(mfrow = c(1,1))
par(ask=F)
summary(as.data.frame(tmp.move))
hist(tmp.move$step)

## More moveHMM Plots
#par(mfrow = c(1,1))
#plot(tmp.move) #being weird 
#plot(tmp.move, compact = TRUE) #being weird



tmp3 <- bind_rows(data.list)
gps.3 <- inner_join(gps.2, tmp3, by = c('i', 'ID'))
gps.3 <- gps.3 %>%  arrange(ID, date.time) %>% 
  mutate(p1 = round(p1, 3), p2 = round(p2, 3),
         step = round(step, 3), angle = round(angle, 3))

gps <- gps.3
str(gps)
#save(gps, animal, juvenile, df.species.season, move.list, file = 'Data 01 GPS DataMoveState.RData')



## ----warning = FALSE------------------------------------------------------------------------------------
par(mfrow = c(1,1))
str(gps)
ggplot(gps, aes(night.cos, p1, colour = species)) +geom_point() + facet_wrap(night ~ . )

ggplot(gps, aes(log(step), p1, colour = species)) + stat_smooth(method="glm", method.args = list(family="binomial")) + facet_wrap(night ~ . )

ggplot(gps, aes(log(step), p2, colour = species)) + stat_smooth(method="glm", method.args = list(family="binomial")) + facet_wrap(night ~ . )


## -------------------------------------------------------------------------------------------------------
ggplot(gps, aes(x, y, colour = p2, size = p2)) + geom_point() + facet_wrap(night ~ . )



## -------------------------------------------------------------------------------------------------------
# Quick function for summarization
simpleCap <- function(x) {          
  tmp <- sapply(x, function(xxxx){
    s <- strsplit(xxxx, " ")[[1]]
    paste(toupper(substring(s, 1,1)), substring(s, 2), sep="", collapse=" ")
  })  # end of sapply
  return(tmp)
}

## Step lengths by behavioral stats by species
b0 <- gps %>% filter(is.finite(step) & step < 15) %>% mutate(state = ifelse(p1 >= 0.5, '1. Slow', '2. Fast'))
b <- b0  %>% 
  group_by(species, state) %>% 
  summarise(step.median = median(step, na.rm = TRUE), .groups = 'drop')
b

## Plot of SLs
ggplot(b0, aes(step)) +
  facet_wrap(species ~ state, scales = 'free') +
  geom_histogram(fill = 'lightblue')

## Make a data frame with these summaries by species
df.species.season <- df.species.season %>% mutate(species = simpleCap(species), season = simpleCap(season))


## ----warning=FALSE--------------------------------------------------------------------------------------
result.list <- vector(mode = 'list', length = nrow(df.species.season))
for (xxx in 1:nrow(df.species.season)){
  print(xxx)
  m <- move.list[[xxx]]
  m.ci <- CI(m)
  df.list <- vector(mode = 'list', length = 4) # List to hold parameter estimates
  # Step Length
  m1 <- m$mle$stepPar
  m1.ci <- m.ci$stepPar
  
  m1.tb <- tibble(Group = 'Movement Parameter', Parameter = 'Step Length Mean', State = c('Slow', 'Fast'), 
                  Estimate = m1[1, ], lcl = m1.ci$lower[1, ], ucl = m1.ci$upper[2, ])
  m2.tb <- tibble(Group = 'Movement Parameter', Parameter = 'Step Length SD', State = c('Slow', 'Fast'), 
                  Estimate = m1[2, ], lcl = m1.ci$lower[2, ], ucl = m1.ci$upper[2, ])
  df.list[[1]] <- bind_rows(m1.tb, m2.tb)
  
  # Turn Angle
  m1 <- m$mle$anglePar
  m1.ci <- m.ci$anglePar
  
  m1.tb <- tibble(Group = 'Movement Parameter', Parameter = 'Turn Angle Mean', State = c('Slow', 'Fast'), 
                  Estimate = m1[1, ], lcl = m1.ci$lower[1, ], ucl = m1.ci$upper[2, ])
  m2.tb <- tibble(Group = 'Movement Parameter', Parameter = 'Turn Angle Concentration', State = c('Slow', 'Fast'), 
                  Estimate = m1[2, ], lcl = m1.ci$lower[2, ], ucl = m1.ci$upper[2, ])
  df.list[[2]] <- bind_rows(m1.tb, m2.tb)
 
  
  # Regression Coeffiencts for transition probabilities
  
  m1 <- m$mle$beta
  m1.ci <- m.ci$beta
  m1.tb <- tibble(Group = 'Transition Coefficient', Parameter = 'Intercept', State = c('Slow to Fast', 'Fast to Slow'), 
                  Estimate = m1[1, ], lcl = m1.ci$lower[1, ], ucl = m1.ci$upper[2, ])
  m2.tb <- tibble(Group = 'Transition Coefficient', Parameter = 'Cosine Hour', State = c('Slow to Fast', 'Fast to Slow'), 
                  Estimate = m1[2, ], lcl = m1.ci$lower[2, ], ucl = m1.ci$upper[2, ])
  df.list[[3]] <- bind_rows(m1.tb, m2.tb)
  df <- bind_rows(df.list)
  df <- df %>% mutate(Species = '', Season = '', .before = Group)
  
  df$Species[1] <- df.species.season$species[xxx]
  df$Season[1] <- df.species.season$season[xxx]
  
  result.list[[xxx]] <- df
}

rm(df, m, m.ci, m1, m1.ci, m1.tb, m2.tb, df.list)


## -------------------------------------------------------------------------------------------------------
m.move.tidy <- bind_rows(result.list)
m.move.tidy <- m.move.tidy %>% mutate(Estimate = sprintf("%.3f", Estimate ), lcl = sprintf("%.3f", lcl), ucl = sprintf("%.3f", ucl)) %>% 
  mutate(Estimate = gsub('NA', '', Estimate), lcl = gsub('NA', '', lcl), ucl = gsub('NA', '', ucl))

m.move.tidy <- m.move.tidy %>% dplyr::rename(LCL = lcl, UCL = ucl, Type = Group)

head(m.move.tidy)


## -------------------------------------------------------------------------------------------------------
?tab_df()
tab_df(m.move.tidy,
       alternate.rows = TRUE, # this colors the rows
       title = "Table S1. Hidden Markov movement model parameter estimates.", #always give
       digits = 3,
       file = "Output/Table S1. Movement Model Parameters.doc")


## -------------------------------------------------------------------------------------------------------
a <- m.move.tidy %>% filter(Parameter == 'Cosine Hour', State == 'Fast to Slow')
print(a)


## -------------------------------------------------------------------------------------------------------
a <- gps %>% mutate(Fast = ifelse(p2 >= 0.5, 1, 0)) 
b1 <- a %>% group_by(species) %>% summarise(PropFast = mean(Fast), .groups = 'drop')
print(b1)

b2 <- a %>% group_by(species, season) %>% summarise(PropFast = mean(Fast), .groups = 'drop')
print(b2)


## -------------------------------------------------------------------------------------------------------
b1 <- a %>% group_by(species, Fast) %>% summarise(StepMean = mean(step, na.rm = TRUE), StepSD = sd(step, na.rm = TRUE), .groups = 'drop')
print(b1)


## -------------------------------------------------------------------------------------------------------
xxx <- 1
m1 <- move.list[[7]]
plotStationary(m1, plotCI = TRUE)

# Modify function to extract plot data
fnc.plot <- function (m, col = NULL, plotCI = TRUE, alpha = 0.95) {
  # if (!is.moveHMM(m)) 
  #   stop("'m' must be a moveHMM object (as output by fitHMM)")
  data <- m$data
  nbStates <- ncol(m$mle$stepPar)
  beta <- m$mle$beta
  if (nrow(beta) == 1) 
    stop("No covariate effect to plot (nrow(beta)==1).")
  if (!is.null(col) & length(col) != nbStates) {
    warning("Length of 'col' should be equal to number of states - argument ignored")
    col <- NULL
  }
  if (is.null(col) & nbStates < 8) {
    pal <- c("#E69F00", "#56B4E9", "#009E73", 
             "#F0E442", "#0072B2", "#D55E00", 
             "#CC79A7")
    col <- pal[1:nbStates]
  }
  if (is.null(col) & nbStates >= 8) {
    hues <- seq(15, 375, length = nbStates + 1)
    col <- hcl(h = hues, l = 65, c = 100)[1:nbStates]
  }
  get_stat <- function(beta, covs, nbStates, i) {
    gamma <- moveHMM:::trMatrix_rcpp(nbStates, beta, covs)[, , 1]
    solve(t(diag(nbStates) - gamma + 1), rep(1, nbStates))[i]
  }
  rawCovs <- m$rawCovs
  gridLength <- 100
  quantSup <- qnorm(1 - (1 - alpha)/2)
  for (cov in 1:ncol(rawCovs)) {
    inf <- min(rawCovs[, cov], na.rm = TRUE)
    sup <- max(rawCovs[, cov], na.rm = TRUE)
    meanCovs <- colMeans(rawCovs)
    tempCovs <- data.frame(rep(meanCovs[1], gridLength))
    if (length(meanCovs) > 1) 
      for (i in 2:length(meanCovs)) tempCovs <- cbind(tempCovs, 
                                                      rep(meanCovs[i], gridLength))
    tempCovs[, cov] <- seq(inf, sup, length = gridLength)
    colnames(tempCovs) <- colnames(rawCovs)
    desMat <- model.matrix(m$conditions$formula, data = tempCovs)
    probs <- stationary(m, covs = desMat)
    plot(tempCovs[, cov], probs[, 1], type = "l", ylim = c(0, 
                                                           1), col = col[1], xlab = names(rawCovs)[cov], ylab = "Stationary state probabilities")
    for (state in 2:nbStates) points(tempCovs[, cov], probs[, 
                                                            state], type = "l", col = col[state])
    legend("topleft", legend = paste("State", 
                                     1:nbStates), col = col, lty = 1, bty = "n")
    if (plotCI) {
      Sigma <- ginv(m$mod$hessian)
      i1 <- length(m$mle$stepPar) + length(m$mle$anglePar) - 
        (!m$conditions$estAngleMean) * nbStates + 1
      i2 <- i1 + length(m$mle$beta) - 1
      gamInd <- i1:i2
      lci <- matrix(NA, gridLength, nbStates)
      uci <- matrix(NA, gridLength, nbStates)
      for (state in 1:nbStates) {
        dN <- t(apply(desMat, 1, function(x) numDeriv::grad(get_stat, 
                                                            beta, covs = matrix(x, nrow = 1), nbStates = nbStates, 
                                                            i = state)))
        se <- t(apply(dN, 1, function(x) suppressWarnings(sqrt(x %*% 
                                                                 Sigma[gamInd, gamInd] %*% x))))
        lci[, state] <- plogis(qlogis(probs[, state]) - 
                                 quantSup * se/(probs[, state] - probs[, state]^2))
        uci[, state] <- plogis(qlogis(probs[, state]) + 
                                 quantSup * se/(probs[, state] - probs[, state]^2))
        options(warn = -1)
        arrows(tempCovs[, cov], lci[, state], tempCovs[, 
                                                       cov], uci[, state], length = 0.025, angle = 90, 
               code = 3, col = col[state], lwd = 0.7)
        options(warn = 1)
      }
    }
  }
  df.list <- list(tempCovs = tempCovs, probs = probs, lci = lci, uci = uci )
  return(df.list)
}


# Practice plot
p <- fnc.plot(m1, plotCI = TRUE)
p1 <- tibble(State = 'Slow', night.cos = p$tempCovs[ ,1], prob = p$probs[ , 1], lcl = p$lci[ , 1], ucl = p$uci[ , 1])
p2 <- tibble(State = 'Fast', night.cos = p$tempCovs[ ,1], prob = p$probs[ , 2], lcl = p$lci[ , 2], ucl = p$uci[ , 2])
p.all <- bind_rows(p1, p2)
ggplot(p.all, aes(night.cos, prob, ymin = lcl, ymax = ucl, group = State, fill = State, col = State)) + 
  geom_ribbon(alpha = 0.5) +
  geom_line()


## ----warning=FALSE--------------------------------------------------------------------------------------
plot.list <- vector(mode = 'list', length = nrow(df.species.season))
for (xxx in 1:nrow(df.species.season)){
  print(xxx)
  m1 <- move.list[[xxx]]
  p <- fnc.plot(m1, plotCI = TRUE)
  
  p1 <- tibble(State = 'Slow', night.cos = p$tempCovs[ ,1], prob = p$probs[ , 1], lcl = p$lci[ , 1], ucl = p$uci[ , 1])
  p2 <- tibble(State = 'Fast', night.cos = p$tempCovs[ ,1], prob = p$probs[ , 2], lcl = p$lci[ , 2], ucl = p$uci[ , 2])
  p.all <- bind_rows(p1, p2)
  p.all <- p.all %>% mutate(Species = df.species.season$species[xxx], Season = df.species.season$season[xxx], .before = State)
  plot.list[[xxx]] <- p.all
}


## -------------------------------------------------------------------------------------------------------
df.plot <- bind_rows(plot.list)
df.plot <- df.plot %>% mutate(Hour = acos(night.cos) * 24 / (2*pi)) %>% 
  mutate(Season = factor(Season, levels = c('Spring', 'Summer', 'Fall', 'Winter')))

a1 <- df.plot  # morning hours
a2 <- df.plot %>% mutate(Hour = 24 - Hour) # Afternoon hours
a <- bind_rows(a1, a2)

ggplot(a, aes(Hour, prob, ymin = lcl, ymax = ucl, group = State, fill = State, col = State)) + 
  theme_bw() +
  facet_grid(Species ~ Season) +
  geom_ribbon(alpha = 0.4, outline.type = 'both', linetype = 0) +
  geom_line() +
  scale_fill_lancet() +
  scale_color_lancet() +
  scale_x_continuous(breaks = c(0, 12, 24)) + #, labels = c('Noon', 'Midnight')) +
  xlab('Hour of day') +
  ylab('Stationary state probability') +
  theme(panel.grid = element_blank(), axis.text = element_text(colour = 'black')) #, axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))
ggsave('Output/Fig. S1. State probability vs night.png', width = 6, height = 5, scale = 0.9)

