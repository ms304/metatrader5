//+------------------------------------------------------------------+
//|                                         Ichimoku2026_Scanner.mq5 |
//|                          Copyright 2026, Invest Data Systems FR. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
// Version avec suivi de confirmation post-détection
// + ANALYSE MACRO : Indice de Momentum USD & Tracking OR
// Signal initial  : transition false -> true (haussier strict)
// Signal confirmé : prix BID > prix_détection ET > SSA_détection ET > SSB_détection
//                   pendant N ticks consécutifs (confirmationTicks)
// Scan            : À chaque nouveau tick

#property copyright "Copyright 2026, Invest Data Systems France."
#property link      "https://ntic974.blogspot.com"
#property version   "1.04"  // Version incrémentée

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Paramètres d'entrée                                              |
//+------------------------------------------------------------------+
input bool enableTrading      = true;
input int  tenkan_period      = 9;
input int  kijun_period       = 26;
input int  senkou_b_period    = 52;
input int  confirmationTicks  = 10;   // Nombre de ticks consécutifs requis pour confirmer

// === NOUVEAU : Paramètres pour l'analyse macro USD ===
input bool enableUSDIndex     = true;   // Activer l'indice de momentum USD
input int  refreshUSDIndex    = 10;     // Recalculer l'indice USD toutes les N secondes

//+------------------------------------------------------------------+
//| Structure de suivi par symbole                                   |
//+------------------------------------------------------------------+
struct SymbolState
  {
   string   name;

   // --- État Ichimoku ---
   bool     prevSignal;        // Signal validé au tick précédent (pour détecter la transition)

   // --- Suivi de confirmation ---
   bool     inConfirmation;    // true : une détection est en cours de confirmation
   bool     confirmed;         // true : signal confirmé déjà émis (évite les doublons)

   double   detectionPrice;    // Close au moment de la détection initiale
   double   detectionSSA;      // Senkou Span A au moment de la détection
   double   detectionSSB;      // Senkou Span B au moment de la détection

   int      confirmCount;      // Nombre de ticks consécutifs où la persistance est vérifiée
   
   // === NOUVEAU : Pour le tracking Macro ===
   bool     isActiveSignal;    // Vrai si le signal est actuellement confirmé
   datetime activeSince;       // Depuis quand le signal est actif
  };

//+------------------------------------------------------------------+
//| Variables globales                                               |
//+------------------------------------------------------------------+
CTrade      trade;
SymbolState g_states[];
int         g_symbolCount = 0;

// === NOUVEAU : Variables pour l'indice USD & Or ===
struct USDMomentumIndex
  {
   int    totalUSDAssets;       // Nombre total d'actifs en USD trackés
   int    bullishCount;         // Combien sont haussiers (confirmés)
   int    bearishCount;         // Combien sont baissiers (on pourrait l'étendre)
   double ratio;                // Bullish / Total
   double score;                // Score de -100 à +100
   datetime lastUpdate;         // Dernier calcul effectué
  };
USDMomentumIndex g_usdIndex;

string g_goldSymbol = "XAUUSD";  // Symbole de l'or (à modifier selon broker)
bool   g_goldDetected = false;    // L'or est-il en signal haussier ?
double g_lastGoldPrice = 0.0;

//+------------------------------------------------------------------+
//| Buffers Ichimoku (réutilisés à chaque appel)                     |
//+------------------------------------------------------------------+
double tenkan_sen_buffer[];
double kijun_sen_buffer[];
double senkou_span_a_buffer[];
double senkou_span_b_buffer[];
double chikou_span_buffer[];
MqlRates mql_rates[];

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ArraySetAsSeries(mql_rates,            true);
   ArraySetAsSeries(tenkan_sen_buffer,    true);
   ArraySetAsSeries(kijun_sen_buffer,     true);
   ArraySetAsSeries(senkou_span_a_buffer, true);
   ArraySetAsSeries(senkou_span_b_buffer, true);
   ArraySetAsSeries(chikou_span_buffer,   true);

   bool onlyMarketWatch = true;
   g_symbolCount = SymbolsTotal(onlyMarketWatch);
   ArrayResize(g_states, g_symbolCount);

   string alreadyValid = "";
   int    alreadyCount = 0;
   
   // Initialisation du compteur USD
   g_usdIndex.totalUSDAssets = 0;
   g_usdIndex.bullishCount = 0;
   g_usdIndex.bearishCount = 0;
   g_usdIndex.lastUpdate = 0;

   for(int i = 0; i < g_symbolCount; i++)
     {
      string sym = SymbolName(i, onlyMarketWatch);
      g_states[i].name           = sym;
      g_states[i].inConfirmation = false;
      g_states[i].confirmed      = false;
      g_states[i].confirmCount   = 0;
      g_states[i].detectionPrice = 0.0;
      g_states[i].detectionSSA   = 0.0;
      g_states[i].detectionSSB   = 0.0;
      g_states[i].isActiveSignal = false;  // === NOUVEAU ===
      g_states[i].activeSince    = 0;

      // Compter les actifs qui sont en USD (filtre simple mais efficace)
      if(enableUSDIndex && StringFind(sym, "USD", 0) >= 0 && StringFind(sym, "USDT", 0) == -1)
        {
         g_usdIndex.totalUSDAssets++;
        }

      // Capturer l'état réel au démarrage (sans alerter)
      double ssa0, ssb0;
      g_states[i].prevSignal = IchimokuBullishStrict(g_states[i].name, ssa0, ssb0);

      if(g_states[i].prevSignal)
        {
         alreadyCount++;
         alreadyValid += g_states[i].name + " ";
        }
     }

   printf("[Ichimoku Scanner] Initialisé sur " + string(g_symbolCount) + " symboles.");
   printf("[Ichimoku Scanner] Déjà validés au démarrage (" + string(alreadyCount) + ") : " + alreadyValid);
   printf("[Ichimoku Scanner] Confirmation requise : " + string(confirmationTicks) + " ticks consécutifs.");
   printf("[Ichimoku Scanner] En attente de nouvelles transitions...");
   
   if(enableUSDIndex)
     {
      printf("[MACRO USD] Tracking activé sur %d actifs USD trouvés.", g_usdIndex.totalUSDAssets);
      printf("[MACRO USD] Indice de Momentum USD (UMI) sera calculé toutes les %d secondes.", refreshUSDIndex);
     }
     
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Déinitialisation                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ArrayFree(g_states);
  }

//+------------------------------------------------------------------+
//| Mise à jour de l'indice USD                                      |
//+------------------------------------------------------------------+
void UpdateUSDMomentumIndex()
  {
   // Ne pas recalculer trop souvent
   if(TimeCurrent() - g_usdIndex.lastUpdate < refreshUSDIndex)
      return;
      
   // Recompter les signaux actifs parmi les USD
   int activeBullish = 0;
   for(int i = 0; i < g_symbolCount; i++)
     {
      if(StringFind(g_states[i].name, "USD", 0) >= 0 && StringFind(g_states[i].name, "USDT", 0) == -1)
        {
         if(g_states[i].confirmed && g_states[i].isActiveSignal)
            activeBullish++;
        }
     }
     
   g_usdIndex.bullishCount = activeBullish;
   g_usdIndex.ratio = (g_usdIndex.totalUSDAssets > 0) ? (double)activeBullish / g_usdIndex.totalUSDAssets : 0.0;
   
   // Calcul du score UMI (USD Momentum Index) : de -100 à +100
   // Formule simple : ratio * 200 - 100
   // Exemple : ratio 0% -> -100 (très baissier USD)
   //          50% -> 0    (neutre)
   //          100% -> +100 (très haussier USD)
   g_usdIndex.score = (g_usdIndex.ratio * 200.0) - 100.0;
   g_usdIndex.lastUpdate = TimeCurrent();
   
   // Analyse complémentaire : interprétation
   string interpretation = "";
   if(g_usdIndex.score >= 60) interpretation = "TRÈS FORT MOMENTUM HAUSSIER USD";
   else if(g_usdIndex.score >= 20) interpretation = "MOMENTUM HAUSSIER USD MODÉRÉ";
   else if(g_usdIndex.score > -20) interpretation = "NEUTRE / SANS DIRECTION CLARÉ";
   else if(g_usdIndex.score > -60) interpretation = "MOMENTUM BAISSIER USD MODÉRÉ";
   else interpretation = "TRÈS FORT MOMENTUM BAISSIER USD";
   
   string msg = StringFormat("[MACRO USD] UMI = %.1f | Ratio: %.1f%% (%d/%d actifs haussiers) | Interprétation: %s",
                             g_usdIndex.score,
                             g_usdIndex.ratio * 100,
                             g_usdIndex.bullishCount,
                             g_usdIndex.totalUSDAssets,
                             interpretation);
   printf(msg);
   
   // === Analyse OR vs USD ===
   if(g_goldDetected)
     {
      string goldMsg = "";
      if(g_usdIndex.score > 50 && g_goldDetected)
         goldMsg = "⚠️ DÉCOUPLAGE POTENTIEL : USD très haussier MAIS Or également haussier (corrélation inverse habituelle brisée)";
      else if(g_usdIndex.score < -50 && g_goldDetected)
         goldMsg = "✅ CORRÉLATION ATTENDUE : USD baissier et Or haussier";
      else if(g_usdIndex.score > 50 && !g_goldDetected)
         goldMsg = "✅ CORRÉLATION ATTENDUE : USD haussier et Or baissier";
         
      if(goldMsg != "")
        {
         printf("[MACRO USD] " + goldMsg);
         if(StringFind(goldMsg, "DÉCOUPLAGE") >= 0)
            Alert(goldMsg);   // Alerte seulement pour les cas exceptionnels
        }
     }
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   string tf = EnumToString(_Period);
   
   // Mise à jour périodique de l'indice macro USD
   if(enableUSDIndex)
      UpdateUSDMomentumIndex();

   for(int i = 0; i < g_symbolCount; i++)
     {
      string sname = g_states[i].name;
      double ssa0  = 0.0;
      double ssb0  = 0.0;
      bool   curSignal = IchimokuBullishStrict(sname, ssa0, ssb0);

      double bid    = SymbolInfoDouble(sname, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(sname, SYMBOL_DIGITS);
      
      // === NOUVEAU : Tracking spécial pour l'or ===
      if(sname == g_goldSymbol)
        {
         g_lastGoldPrice = bid;
        }

      //----------------------------------------------------------------
      // 1. Détection de transition false -> true
      //----------------------------------------------------------------
      if(curSignal && !g_states[i].prevSignal)
        {
         // Récupérer le close de la bougie courante comme prix de référence
         MqlRates rates[];
         ArraySetAsSeries(rates, true);
         double refPrice = bid; // fallback
         if(CopyRates(sname, PERIOD_CURRENT, 0, 1, rates) > 0)
            refPrice = rates[0].close;

         // Initialiser le suivi de confirmation
         g_states[i].inConfirmation = true;
         g_states[i].confirmed      = false;
         g_states[i].confirmCount   = 0;
         g_states[i].detectionPrice = refPrice;
         g_states[i].detectionSSA   = ssa0;
         g_states[i].detectionSSB   = ssb0;
         
         // === NOUVEAU : Reset status actif ===
         g_states[i].isActiveSignal = false;

         string msg = "[Ichimoku Scanner] SIGNAL HAUSSIER STRICT : " + sname
                      + " | TF: " + tf
                      + " | Prix détection: " + DoubleToString(refPrice, digits)
                      + " | SSA: " + DoubleToString(ssa0, digits)
                      + " | SSB: " + DoubleToString(ssb0, digits)
                      + " | " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

         printf(msg);
         Alert(msg);
         SendNotification(msg);
        }

      //----------------------------------------------------------------
      // 2. Suivi de confirmation (si une détection est en cours)
      //----------------------------------------------------------------
      if(g_states[i].inConfirmation)
        {
         // Vérifier si le signal Ichimoku est toujours validé
         if(!curSignal)
           {
            // Signal invalidé : reset du suivi
            string resetMsg = "[Ichimoku Scanner] SUIVI ANNULÉ : " + sname
                              + " | Signal invalidé après " + string(g_states[i].confirmCount) + " ticks"
                              + " | " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
            printf(resetMsg);

            g_states[i].inConfirmation = false;
            g_states[i].confirmed      = false;
            g_states[i].confirmCount   = 0;
            g_states[i].isActiveSignal = false;
           }
         else
           {
            // Signal toujours validé : vérifier la persistance du prix
            bool priceAboveDetection = (bid > g_states[i].detectionPrice);
            bool priceAboveSSA       = (bid > g_states[i].detectionSSA);
            bool priceAboveSSB       = (bid > g_states[i].detectionSSB);
            bool persistenceOK       = (priceAboveDetection && priceAboveSSA && priceAboveSSB);

            if(persistenceOK)
              {
               g_states[i].confirmCount++;
              }
            else
              {
               // La persistance est rompue : on remet le compteur à zéro
               // mais on reste en mode "inConfirmation" (le signal Ichimoku tient encore)
               if(g_states[i].confirmCount > 0)
                 {
                  string breakMsg = "[Ichimoku Scanner] PERSISTANCE ROMPUE : " + sname
                                    + " | BID: " + DoubleToString(bid, digits)
                                    + " > PrixDét: " + string(priceAboveDetection ? "OK" : "KO")
                                    + " > SSA: " + string(priceAboveSSA ? "OK" : "KO")
                                    + " > SSB: " + string(priceAboveSSB ? "OK" : "KO")
                                    + " | Compteur remis à 0"
                                    + " | " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
                  printf(breakMsg);
                 }
               g_states[i].confirmCount = 0;
            }

            // 3. Vérification du seuil de confirmation
            if(!g_states[i].confirmed && g_states[i].confirmCount >= confirmationTicks)
              {
               g_states[i].confirmed = true;
               g_states[i].isActiveSignal = true;   // === NOUVEAU : Marquer comme actif pour l'indice
               g_states[i].activeSince = TimeCurrent();

               string confMsg = "[Ichimoku Scanner] *** SIGNAL CONFIRMÉ *** : " + sname
                                + " | TF: " + tf
                                + " | BID: " + DoubleToString(bid, digits)
                                + " | Ticks persistants: " + string(g_states[i].confirmCount)
                                + " | PrixDét: " + DoubleToString(g_states[i].detectionPrice, digits)
                                + " | SSA réf: " + DoubleToString(g_states[i].detectionSSA, digits)
                                + " | SSB réf: " + DoubleToString(g_states[i].detectionSSB, digits)
                                + " | " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

               printf(confMsg);
               Alert(confMsg);
               SendNotification(confMsg);
               
               // === NOUVEAU : Si c'est l'or, le tracker se met à jour ===
               if(sname == g_goldSymbol)
                 {
                  g_goldDetected = true;
                  printf("[MACRO OR] XAUUSD est maintenant en tendance haussière Ichimoku confirmée.");
                 }
              }
           }
        }
        
      // === NOUVEAU : Gérer la fin d'un signal actif ===
      if(g_states[i].isActiveSignal && !curSignal)
        {
         // Le signal n'est plus valide (Ichimoku cassé)
         g_states[i].isActiveSignal = false;
         g_states[i].confirmed = false;
         printf("[Ichimoku Scanner] FIN DE SIGNAL : %s (actif depuis %s)", 
                sname, TimeToString(g_states[i].activeSince));
                
         if(sname == g_goldSymbol)
           {
            g_goldDetected = false;
            printf("[MACRO OR] XAUUSD n'est plus en tendance haussière Ichimoku.");
           }
        }

      // Mémoriser l'état courant
      g_states[i].prevSignal = curSignal;
     }
  }

//+------------------------------------------------------------------+
//| Calcule le signal haussier strict et retourne SSA/SSB courants   |
//+------------------------------------------------------------------+
bool IchimokuBullishStrict(string sname, double &out_ssa, double &out_ssb)
  {
   int max    = 64;
   int handle = iIchimoku(sname, PERIOD_CURRENT, tenkan_period, kijun_period, senkou_b_period);

   if(handle == INVALID_HANDLE)
      return false;

   int nbt   = CopyBuffer(handle, TENKANSEN_LINE,   0, max, tenkan_sen_buffer);
   int nbk   = CopyBuffer(handle, KIJUNSEN_LINE,    0, max, kijun_sen_buffer);
   int nbssa = CopyBuffer(handle, SENKOUSPANA_LINE, 0, max, senkou_span_a_buffer);
   int nbssb = CopyBuffer(handle, SENKOUSPANB_LINE, 0, max, senkou_span_b_buffer);
   int nbc   = CopyBuffer(handle, CHIKOUSPAN_LINE,  0, max, chikou_span_buffer);

   if(nbt <= 0 || nbk <= 0 || nbssa <= 0 || nbssb <= 0 || nbc <= 0)
     {
      IndicatorRelease(handle);
      return false;
     }

   if(CopyRates(sname, PERIOD_CURRENT, 0, 32, mql_rates) <= 0)
     {
      IndicatorRelease(handle);
      return false;
     }

   double close0  = mql_rates[0].close;
   double ssa0    = senkou_span_a_buffer[0];
   double ssb0    = senkou_span_b_buffer[0];
   double tenkan0 = tenkan_sen_buffer[0];
   double kijun0  = kijun_sen_buffer[0];

   double cs        = chikou_span_buffer[26];
   double ssb_cs    = senkou_span_b_buffer[26];
   double ssa_cs    = senkou_span_a_buffer[27];
   double tenkan_cs = tenkan_sen_buffer[27];
   double kijun_cs  = kijun_sen_buffer[26];

   IndicatorRelease(handle);

   ArrayFree(senkou_span_b_buffer);
   ArrayFree(senkou_span_a_buffer);
   ArrayFree(tenkan_sen_buffer);
   ArrayFree(kijun_sen_buffer);
   ArrayFree(chikou_span_buffer);
   ArrayFree(mql_rates);

   ArraySetAsSeries(mql_rates,            true);
   ArraySetAsSeries(tenkan_sen_buffer,    true);
   ArraySetAsSeries(kijun_sen_buffer,     true);
   ArraySetAsSeries(senkou_span_a_buffer, true);
   ArraySetAsSeries(senkou_span_b_buffer, true);
   ArraySetAsSeries(chikou_span_buffer,   true);

   bool priceAboveCloud = (close0 > ssb0 && close0 > ssa0);
   bool priceAboveLines = (close0 > tenkan0 && close0 > kijun0);
   bool chikouValidated = (cs > tenkan_cs && cs > kijun_cs && cs > ssa_cs && cs > ssb_cs);

   // Exposer SSA/SSB courants pour le suivi de confirmation
   out_ssa = ssa0;
   out_ssb = ssb0;

   return (priceAboveCloud && priceAboveLines && chikouValidated);
  }

//+------------------------------------------------------------------+
//| Retourne true uniquement sur la première bougie d'un nouveau bar |
//+------------------------------------------------------------------+
bool isNewBar()
  {
   static datetime last_time = 0;
   datetime lastbar_time = SeriesInfoInteger(Symbol(), Period(), SERIES_LASTBAR_DATE);

   if(last_time == 0)
     {
      last_time = lastbar_time;
      return false;
     }

   if(last_time != lastbar_time)
     {
      last_time = lastbar_time;
      return true;
     }

   return false;
  }
//+------------------------------------------------------------------+
