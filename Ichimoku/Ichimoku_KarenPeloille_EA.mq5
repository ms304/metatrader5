//+------------------------------------------------------------------+
//|                    Ichimoku_KarenPeloille_EA.mq5                 |
//|          Expert Advisor - Méthode Ichimoku Karen Péloille        |
//|          Analyse multi-actifs, multi-unités de temps             |
//+------------------------------------------------------------------+
#property copyright   "Ichimoku EA - Méthode Karen Péloille - Didier V. Le HPI Réunionnais"
#property version     "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Paramètres d'entrée                                              |
//+------------------------------------------------------------------+
input group "=== PARAMÈTRES ICHIMOKU ==="
input int    InpTenkanPeriod    = 9;    // Période Tenkan-Sen
input int    InpKijunPeriod     = 26;   // Période Kijun-Sen
input int    InpSenkouBPeriod   = 52;   // Période Senkou Span B
input int    InpDisplacement    = 26;   // Décalage Chikou/Kumo

input group "=== GESTION DU RISQUE ==="
input double InpRiskPercent     = 1.0;  // Risque par trade (%)
input double InpSLMultiplier    = 1.5;  // Multiplicateur SL (x Kijun distance)
input double InpTPRatio         = 2.0;  // Ratio TP/SL

input group "=== FILTRES ==="
input bool   InpTradeM1         = false; // Analyser M1
input bool   InpTradeM5         = false; // Analyser M5
input bool   InpTradeM15        = true;  // Analyser M15
input bool   InpTradeM30        = true;  // Analyser M30
input bool   InpTradeH1         = true;  // Analyser H1
input bool   InpTradeH4         = true;  // Analyser H4
input bool   InpTradeD1         = true;  // Analyser D1
input bool   InpTradeW1         = true;  // Analyser W1
input bool   InpTradeMN         = false; // Analyser MN

input group "=== LOG ==="
input string InpLogFileName     = "IchimokuKP_Log.txt"; // Nom du fichier de log
input bool   InpVerboseLog      = true;  // Log détaillé

input group "=== EXÉCUTION ==="
input bool   InpAutoTrade       = false; // Exécuter les trades automatiquement
input int    InpMagicNumber     = 202406; // Numéro magique
input int    InpMaxPositions    = 5;     // Positions max simultanées

//+------------------------------------------------------------------+
//| Structures de données                                            |
//+------------------------------------------------------------------+
struct IchimokuValues
{
   double tenkan;
   double kijun;
   double senkouA;       // Span A actuelle
   double senkouB;       // Span B actuelle
   double senkouA_fwd;   // Span A future (kumo futur)
   double senkouB_fwd;   // Span B future (kumo futur)
   double chikou;        // Lagging Span
   double price_at_chikou; // Prix à la position du chikou (26 bougies en arrière)
   double kumo_at_chikou_A; // Span A à la position du chikou
   double kumo_at_chikou_B; // Span B à la position du chikou
};

struct TradeSetup
{
   string   symbol;
   ENUM_TIMEFRAMES timeframe;
   string   direction;      // "BUY" ou "SELL"
   double   entryPrice;
   double   stopLoss;
   double   takeProfit;
   double   lotSize;
   int      score;          // Score de qualité du setup (0-10)
   string   reasons[];      // Raisons du setup
   string   warnings[];     // Alertes/faiblesses
   bool     isValid;
};

struct SymbolAnalysis
{
   string   symbol;
   bool     isOpen;
   bool     hasSetup;
   TradeSetup bestSetup;
};

//+------------------------------------------------------------------+
//| Variables globales                                               |
//+------------------------------------------------------------------+
CTrade        g_trade;
CSymbolInfo   g_symbolInfo;
CPositionInfo g_posInfo;
CAccountInfo  g_accountInfo;

string        g_logPath;
datetime      g_lastAnalysisTime = 0;
int           g_analysisInterval = 300; // 5 minutes entre analyses

ENUM_TIMEFRAMES g_timeframes[];
string          g_tfNames[];

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   
   // Chemin du fichier log
   g_logPath = InpLogFileName;
   
   // Construction du tableau des timeframes actifs
   BuildTimeframeList();
   
   // Log de démarrage
   string startMsg = "\n" + StringRepeat("=", 70) + "\n";
   startMsg += "  ICHIMOKU EXPERT ADVISOR - MÉTHODE KAREN PÉLOILLE\n";
   startMsg += "  Démarrage: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\n";
   startMsg += "  Compte: " + IntegerToString((int)g_accountInfo.Login()) + 
               " | Solde: " + DoubleToString(g_accountInfo.Balance(), 2) + " " + 
               g_accountInfo.Currency() + "\n";
   startMsg += "  Risk/trade: " + DoubleToString(InpRiskPercent, 1) + "%" + 
               " | Magic: " + IntegerToString(InpMagicNumber) + "\n";
   startMsg += "  Mode: " + (InpAutoTrade ? "TRADING AUTOMATIQUE ACTIF" : "Analyse uniquement") + "\n";
   startMsg += StringRepeat("=", 70);
   WriteLog(startMsg);
   
   Print("Ichimoku KP EA démarré. Log: ", g_logPath);
   
   // Première analyse immédiate
   RunFullAnalysis();
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialisation                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   string msg = "\n" + StringRepeat("-", 70) + "\n";
   msg += "EA arrêté. Raison: " + IntegerToString(reason) + 
          " | " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   msg += "\n" + StringRepeat("-", 70);
   WriteLog(msg);
}

//+------------------------------------------------------------------+
//| Tick principal                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   
   // Analyse toutes les X minutes
   if(now - g_lastAnalysisTime >= g_analysisInterval)
   {
      RunFullAnalysis();
      g_lastAnalysisTime = now;
   }
}

//+------------------------------------------------------------------+
//| Analyse complète de tous les actifs du Market Watch             |
//+------------------------------------------------------------------+
void RunFullAnalysis()
{
   string header = "\n" + StringRepeat("*", 70) + "\n";
   header += "  ANALYSE ICHIMOKU COMPLÈTE\n";
   header += "  Date/Heure: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) + "\n";
   header += "  Solde: " + DoubleToString(g_accountInfo.Balance(), 2) + " " + g_accountInfo.Currency() +
             " | Equity: " + DoubleToString(g_accountInfo.Equity(), 2) + "\n";
   header += StringRepeat("*", 70);
   WriteLog(header);
   
   int symbolCount = SymbolsTotal(true); // true = seulement Market Watch
   int setupCount  = 0;
   double totalRisk = 0;
   
   TradeSetup allSetups[];
   string     allSetupsSymbols[];
   
   WriteLog("\n[SCAN] " + IntegerToString(symbolCount) + " actif(s) dans le Market Watch");
   
   for(int i = 0; i < symbolCount; i++)
   {
      string sym = SymbolName(i, true);
      if(sym == "") continue;
      
      // Vérification tradabilité
      bool tradable = IsSymbolTradable(sym);
      string tradableStr = tradable ? "OUVERT" : "FERMÉ/NON TRADABLE";
      
      WriteLog("\n" + StringRepeat("-", 60));
      WriteLog("[ACTIF] " + sym + " | Marché: " + tradableStr);
      
      if(!tradable)
      {
         WriteLog("  >> Actif ignoré pour le trading (marché fermé ou non tradable)");
         // On analyse quand même pour information
      }
      
      // Analyse Ichimoku sur tous les timeframes
      bool symbolHasSetup = false;
      for(int t = 0; t < ArraySize(g_timeframes); t++)
      {
         TradeSetup setup;
         if(AnalyzeIchimoku(sym, g_timeframes[t], g_tfNames[t], setup))
         {
            if(setup.isValid && tradable)
            {
               int sz = ArraySize(allSetups);
               ArrayResize(allSetups, sz + 1);
               ArrayResize(allSetupsSymbols, sz + 1);
               allSetups[sz] = setup;
               allSetupsSymbols[sz] = sym + " " + g_tfNames[t];
               setupCount++;
               symbolHasSetup = true;
            }
         }
      }
      
      if(!symbolHasSetup)
         WriteLog("  >> Aucun setup valide identifié sur " + sym);
   }
   
   // Résumé des setups trouvés
   WriteSummary(allSetups, allSetupsSymbols, setupCount);
   
   // Exécution si mode auto
   if(InpAutoTrade && setupCount > 0)
      ExecuteSetups(allSetups, allSetupsSymbols);
}

//+------------------------------------------------------------------+
//| Vérification si l'actif est tradable                            |
//+------------------------------------------------------------------+
bool IsSymbolTradable(const string symbol)
{
   // Vérification existence du symbole
   if(!SymbolSelect(symbol, true)) return false;
   
   // Vérification du mode trading
   int tradeMode = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED) return false;
   
   // Vérification sessions de trading
   datetime serverTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(serverTime, dt);
   
   // Vérification via bid/ask - si 0, marché probablement fermé
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return false;
   
   // Vérification spread anormal (spread > 5% du prix = suspect)
   double spread = ask - bid;
   if(bid > 0 && spread / bid > 0.05) 
   {
      WriteLog("  [WARN] Spread anormal sur " + symbol + ": " + 
               DoubleToString(spread / bid * 100, 2) + "%");
      return false;
   }
   
   // Vérification via SYMBOL_SESSION_OPEN (si disponible)
   // Pour les actions/indices, vérifier les heures de session
   long sessionDeals = SymbolInfoInteger(symbol, SYMBOL_TRADE_CALC_MODE);
   
   return true;
}

//+------------------------------------------------------------------+
//| Analyse Ichimoku complète sur un symbole/timeframe              |
//+------------------------------------------------------------------+
bool AnalyzeIchimoku(const string symbol, const ENUM_TIMEFRAMES tf, 
                      const string tfName, TradeSetup &setup)
{
   // Récupération des données Ichimoku
   int handle = iIchimoku(symbol, tf, InpTenkanPeriod, InpKijunPeriod, InpSenkouBPeriod);
   if(handle == INVALID_HANDLE)
   {
      WriteLog("  [ERR] Impossible de créer indicateur Ichimoku sur " + symbol + " " + tfName);
      return false;
   }
   
   // ----------------------------------------------------------------
   // BUFFERS MT5 ICHIMOKU - DÉCALAGES CORRECTS
   //
   // Dans MT5, iIchimoku retourne :
   //   Buffer 0 : Tenkan-Sen        → index 0 = bougie actuelle (pas de décalage)
   //   Buffer 1 : Kijun-Sen         → index 0 = bougie actuelle (pas de décalage)
   //   Buffer 2 : Senkou Span A     → DÉCALÉ +26 dans le FUTUR
   //                                  index 0        = valeur dans 26 bougies (futur)
   //                                  index 26       = valeur actuelle (alignée sur la bougie courante)
   //   Buffer 3 : Senkou Span B     → même décalage que Span A
   //   Buffer 4 : Chikou Span       → DÉCALÉ -26 dans le PASSÉ
   //                                  index 0        = cellule vide / DBL_MAX (dans le futur)
   //                                  index 26       = close actuel (affiché 26 bougies en arrière)
   //                                  index 26+26=52 = valeur du chikou il y a 26 bougies
   // ----------------------------------------------------------------
   
   // On a besoin de bougies supplémentaires pour les décalages
   int barsNeeded = InpSenkouBPeriod + InpDisplacement * 3 + 20;
   
   double tenkan[], kijun[], senkouA[], senkouB[], chikou[];
   ArraySetAsSeries(tenkan,  true);
   ArraySetAsSeries(kijun,   true);
   ArraySetAsSeries(senkouA, true);
   ArraySetAsSeries(senkouB, true);
   ArraySetAsSeries(chikou,  true);
   
   // Pour le chikou on doit lire depuis -InpDisplacement pour capturer index 26
   // CopyBuffer avec start_pos=0 et count=barsNeeded suffit car ArraySetAsSeries=true
   if(CopyBuffer(handle, 0, 0, barsNeeded, tenkan)  < barsNeeded ||
      CopyBuffer(handle, 1, 0, barsNeeded, kijun)   < barsNeeded ||
      CopyBuffer(handle, 2, 0, barsNeeded, senkouA) < barsNeeded ||
      CopyBuffer(handle, 3, 0, barsNeeded, senkouB) < barsNeeded ||
      CopyBuffer(handle, 4, 0, barsNeeded, chikou)  < barsNeeded)
   {
      IndicatorRelease(handle);
      if(InpVerboseLog)
         WriteLog("  [" + tfName + "] Données insuffisantes sur " + symbol);
      return false;
   }
   
   IndicatorRelease(handle);
   
   // Prix actuels
   double close[], high[], low[], open[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(open,  true);
   
   if(CopyClose(symbol, tf, 0, barsNeeded, close) < barsNeeded) return false;
   if(CopyHigh(symbol,  tf, 0, barsNeeded, high)  < barsNeeded) return false;
   if(CopyLow(symbol,   tf, 0, barsNeeded, low)   < barsNeeded) return false;
   if(CopyOpen(symbol,  tf, 0, barsNeeded, open)  < barsNeeded) return false;
   
   // ----------------------------------------------------------------
   // LECTURE CORRECTE DES VALEURS ICHIMOKU
   // ----------------------------------------------------------------
   IchimokuValues ich;
   ich.tenkan = tenkan[0];
   ich.kijun  = kijun[0];
   
   // Senkou Span A et B (Kumo) :
   //   senkouA[0]               = futur (+26 bougies)
   //   senkouA[InpDisplacement] = valeur actuelle du Kumo (alignée sur la bougie courante)
   ich.senkouA_fwd = senkouA[0];                    // Kumo futur (+26)
   ich.senkouB_fwd = senkouB[0];
   ich.senkouA     = senkouA[InpDisplacement];       // Kumo actuel
   ich.senkouB     = senkouB[InpDisplacement];
   
   // Chikou Span (Lagging Span) :
   //   chikou[InpDisplacement] = close actuel affiché 26 bougies en arrière
   //                             C'est la valeur à comparer aux prix passés
   //   chikou[0] et les premiers indices = VIDES (DBL_MAX) car dans le futur
   //
   // Valeur du chikou = close de la bougie actuelle
   // On utilise directement close[0] qui est identique à chikou[InpDisplacement]
   ich.chikou = close[0]; // = chikou[InpDisplacement] = valeur réelle du Chikou
   
   // Pour l'analyse du Chikou, on le compare aux prix qui se trouvent
   // visuellement sous lui sur le graphique, soit les prix il y a 26 bougies
   ich.price_at_chikou  = close[InpDisplacement];    // Prix t-26
   
   // Kumo là où le chikou se trouve visuellement (t-26) :
   // Le kumo à t-26 = senkouA/B lus à l'index correspondant
   // senkouA est décalé de +26, donc à t-26 on lit senkouA[InpDisplacement + InpDisplacement]
   ich.kumo_at_chikou_A = senkouA[InpDisplacement * 2]; // Kumo à t-26
   ich.kumo_at_chikou_B = senkouB[InpDisplacement * 2];
   
   double currentPrice = close[0];
   double currentHigh  = high[0];
   double currentLow   = low[0];

   // VALIDATION - protection contre DBL_MAX / données vides
   double DBL_LIMIT = 1e15;
   if(ich.tenkan      <= 0 || ich.tenkan      > DBL_LIMIT ||
      ich.kijun       <= 0 || ich.kijun       > DBL_LIMIT ||
      ich.senkouA     <= 0 || ich.senkouA     > DBL_LIMIT ||
      ich.senkouB     <= 0 || ich.senkouB     > DBL_LIMIT ||
      ich.senkouA_fwd <= 0 || ich.senkouA_fwd > DBL_LIMIT ||
      ich.senkouB_fwd <= 0 || ich.senkouB_fwd > DBL_LIMIT ||
      ich.chikou      <= 0 || ich.chikou      > DBL_LIMIT ||
      ich.price_at_chikou <= 0 || currentPrice <= 0)
   {
      if(InpVerboseLog)
         WriteLog("  [" + tfName + "] Valeurs Ichimoku invalides sur " + symbol +
                  " - donnees insuffisantes ou actif non supporte");
      setup.isValid = false;
      return false;
   }
   // Filtrage qualité des données :
   // Si le Kumo actuel ET futur sont inférieurs à 3 points d'épaisseur,
   // les données Ichimoku sont trop compressées pour être exploitables sur ce TF.
   double onePoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double minKumoThickness = 3.0 * onePoint;
   double kumoNow  = MathAbs(ich.senkouA    - ich.senkouB);
   double kumoFut  = MathAbs(ich.senkouA_fwd - ich.senkouB_fwd);
   if(kumoNow < minKumoThickness && kumoFut < minKumoThickness)
   {
      if(InpVerboseLog)
         WriteLog("  [" + tfName + "] Kumo trop plat (" + DoubleToString(kumoNow/onePoint,1) + " pts) sur " + symbol + " - TF ignore");
      setup.isValid = false;
      return false;
   }

   // ================================================================
   // ANALYSE ICHIMOKU KAREN PÉLOILLE - CRITÈRES COMPLETS
   // ================================================================
   
   string logEntry = "\n  [" + tfName + "] Analyse " + symbol + "\n";
   logEntry += "  Prix: " + DoubleToString(currentPrice, _Digits) + 
               " | T: " + DoubleToString(ich.tenkan, _Digits) + 
               " | K: " + DoubleToString(ich.kijun, _Digits) + "\n";
   logEntry += "  Kumo: [" + DoubleToString(MathMin(ich.senkouA, ich.senkouB), _Digits) + 
               " - " + DoubleToString(MathMax(ich.senkouA, ich.senkouB), _Digits) + "]" +
               " | Kumo futur: [" + DoubleToString(MathMin(ich.senkouA_fwd, ich.senkouB_fwd), _Digits) + 
               " - " + DoubleToString(MathMax(ich.senkouA_fwd, ich.senkouB_fwd), _Digits) + "]\n";
   logEntry += "  Chikou: " + DoubleToString(ich.chikou, _Digits) + 
               " vs Prix t-26: " + DoubleToString(ich.price_at_chikou, _Digits);
   
   WriteLog(logEntry);
   
   // Évaluation directionnelle
   int bullScore = 0;
   int bearScore = 0;
   string bullReasons[], bearReasons[];
   string warnings[];
   
   // ----------------------------------------------------------------
   // CRITÈRE 1: POSITION DU PRIX PAR RAPPORT AU KUMO
   // ----------------------------------------------------------------
   double kumoTop    = MathMax(ich.senkouA, ich.senkouB);
   double kumoBottom = MathMin(ich.senkouA, ich.senkouB);
   double kumoThickness = kumoTop - kumoBottom;
   
   bool priceAboveKumo = currentPrice > kumoTop;
   bool priceBelowKumo = currentPrice < kumoBottom;
   bool priceInKumo    = !priceAboveKumo && !priceBelowKumo;
   
   string kumoPos;
   if(priceAboveKumo)      { kumoPos = "AU-DESSUS du Kumo (HAUSSIER)"; bullScore += 2; AddToArray(bullReasons, "Prix au-dessus du Kumo"); }
   else if(priceBelowKumo) { kumoPos = "EN-DESSOUS du Kumo (BAISSIER)"; bearScore += 2; AddToArray(bearReasons, "Prix en-dessous du Kumo"); }
   else                    { kumoPos = "DANS le Kumo (neutre/danger)"; AddToArray(warnings, "Prix dans le Kumo - signal faible"); }
   
   WriteLog("  C1 - Position/Kumo: " + kumoPos);
   
   // ----------------------------------------------------------------
   // CRITÈRE 2: COULEUR DU KUMO (NUAGE) - Senkou A > Senkou B = haussier
   // ----------------------------------------------------------------
   bool kumoHaussier = ich.senkouA > ich.senkouB;
   bool kumoFuturHaussier = ich.senkouA_fwd > ich.senkouB_fwd;
   
   string kumoColor  = kumoHaussier ? "VERT (haussier)" : "ROUGE (baissier)";
   string kumoFutur  = kumoFuturHaussier ? "VERT (haussier)" : "ROUGE (baissier)";
   
   if(kumoHaussier) { bullScore += 1; AddToArray(bullReasons, "Kumo vert (SA > SB)"); }
   else             { bearScore += 1; AddToArray(bearReasons, "Kumo rouge (SB > SA)"); }
   
   if(kumoFuturHaussier) { bullScore += 1; AddToArray(bullReasons, "Kumo futur vert"); }
   else                  { bearScore += 1; AddToArray(bearReasons, "Kumo futur rouge"); }
   
   WriteLog("  C2 - Kumo actuel: " + kumoColor + " | Kumo futur: " + kumoFutur);
   
   // ----------------------------------------------------------------
   // CRITÈRE 3: POSITION TENKAN PAR RAPPORT AU KIJUN
   // ----------------------------------------------------------------
   bool tenkanAboveKijun = ich.tenkan > ich.kijun;
   
   if(tenkanAboveKijun) { bullScore += 1; AddToArray(bullReasons, "Tenkan > Kijun"); }
   else if(ich.tenkan < ich.kijun) { bearScore += 1; AddToArray(bearReasons, "Tenkan < Kijun"); }
   else AddToArray(warnings, "Tenkan = Kijun (compression)");
   
   WriteLog("  C3 - Tenkan/Kijun: " + (tenkanAboveKijun ? "T > K (haussier)" : 
            (ich.tenkan < ich.kijun ? "T < K (baissier)" : "T = K (neutre)")));
   
   // ----------------------------------------------------------------
   // CRITÈRE 4: CROISEMENT TENKAN/KIJUN (TK Cross - signal fort KP)
   // ----------------------------------------------------------------
   double prevTenkan = tenkan[1];
   double prevKijun  = kijun[1];
   
   bool tkGoldenCross = (prevTenkan <= prevKijun) && (ich.tenkan > ich.kijun);
   bool tkDeathCross  = (prevTenkan >= prevKijun) && (ich.tenkan < ich.kijun);
   
   if(tkGoldenCross) 
   { 
      bullScore += 3; 
      AddToArray(bullReasons, "TK Golden Cross (croisement haussier Tenkan/Kijun)");
      WriteLog("  C4 - TK CROSS: *** GOLDEN CROSS HAUSSIER ***");
   }
   else if(tkDeathCross) 
   { 
      bearScore += 3; 
      AddToArray(bearReasons, "TK Death Cross (croisement baissier Tenkan/Kijun)");
      WriteLog("  C4 - TK CROSS: *** DEATH CROSS BAISSIER ***");
   }
   else
   {
      WriteLog("  C4 - TK CROSS: Pas de croisement");
   }
   
   // ----------------------------------------------------------------
   // CRITÈRE 5: POSITION DU PRIX PAR RAPPORT AU TENKAN ET KIJUN
   // ----------------------------------------------------------------
   bool priceAboveTenkan = currentPrice > ich.tenkan;
   bool priceAboveKijun  = currentPrice > ich.kijun;
   
   if(priceAboveTenkan && priceAboveKijun) 
   { 
      bullScore += 1; 
      AddToArray(bullReasons, "Prix > Tenkan et Prix > Kijun");
   }
   else if(!priceAboveTenkan && !priceAboveKijun) 
   { 
      bearScore += 1; 
      AddToArray(bearReasons, "Prix < Tenkan et Prix < Kijun");
   }
   
   WriteLog("  C5 - Prix/TK: " + (priceAboveTenkan ? "Prix>T" : "Prix<T") + 
            " | " + (priceAboveKijun ? "Prix>K" : "Prix<K"));
   
   // ----------------------------------------------------------------
   // CRITÈRE 6: LAGGING SPAN (CHIKOU) - Critère ESSENTIEL selon KP
   // ----------------------------------------------------------------
   // Le Chikou doit être au-dessus des prix passés ET au-dessus du kumo passé
   
   // Tolérance = max(5 points, 0.05% du prix) pour éviter faux signaux sur égalités
   // floating-point. Exemple ADAUSD 0.25: 0.05% = 0.000125 >> 5 pts = 0.00005
   double chikouTol = MathMax(5.0 * onePoint, currentPrice * 0.0005);
   bool chikouAbovePrice  = ich.chikou > ich.price_at_chikou + chikouTol;
   bool chikouBelowPrice  = ich.chikou < ich.price_at_chikou - chikouTol;
   // Si les deux sont faux : Chikou ≈ prix passé → neutre (zone de congestion)
   
   double kumoTopAtChikou    = MathMax(ich.kumo_at_chikou_A, ich.kumo_at_chikou_B);
   double kumoBottomAtChikou = MathMin(ich.kumo_at_chikou_A, ich.kumo_at_chikou_B);
   bool chikouAboveKumo = ich.chikou > kumoTopAtChikou    + chikouTol;
   bool chikouBelowKumo = ich.chikou < kumoBottomAtChikou - chikouTol;
   bool chikouInKumo    = !chikouAboveKumo && !chikouBelowKumo;
   
   string chikouAnalysis;
   if(chikouAbovePrice && chikouAboveKumo)
   {
      bullScore += 3; // Critère majeur KP
      AddToArray(bullReasons, "Chikou au-dessus des prix ET au-dessus du Kumo passé (signal fort)");
      chikouAnalysis = "HAUSSIER FORT (au-dessus prix + Kumo)";
   }
   else if(chikouAbovePrice && chikouInKumo)
   {
      bullScore += 1;
      AddToArray(bullReasons, "Chikou au-dessus des prix (dans Kumo passé)");
      AddToArray(warnings, "Chikou traverse le Kumo passé - signal modéré");
      chikouAnalysis = "HAUSSIER MODÉRÉ (au-dessus prix, dans Kumo)";
   }
   else if(chikouBelowPrice && chikouBelowKumo)
   {
      bearScore += 3; // Critère majeur KP
      AddToArray(bearReasons, "Chikou en-dessous des prix ET en-dessous du Kumo passé (signal fort)");
      chikouAnalysis = "BAISSIER FORT (en-dessous prix + Kumo)";
   }
   else if(chikouBelowPrice && chikouInKumo)
   {
      bearScore += 1;
      AddToArray(bearReasons, "Chikou en-dessous des prix (dans Kumo passé)");
      AddToArray(warnings, "Chikou traverse le Kumo passé - signal modéré");
      chikouAnalysis = "BAISSIER MODÉRÉ (en-dessous prix, dans Kumo)";
   }
   else
   {
      AddToArray(warnings, "Chikou en zone neutre ou contradictoire");
      chikouAnalysis = "NEUTRE / CONTRADICTOIRE";
   }
   
   WriteLog("  C6 - CHIKOU (Lagging Span): " + chikouAnalysis);
   WriteLog("       Chikou=" + DoubleToString(ich.chikou, _Digits) + 
            " | Prix t-26=" + DoubleToString(ich.price_at_chikou, _Digits) +
            " | Kumo t-52=[" + DoubleToString(kumoBottomAtChikou, _Digits) + 
            "-" + DoubleToString(kumoTopAtChikou, _Digits) + "]");
   
   // ----------------------------------------------------------------
   // CRITÈRE 7: POSITION DU PRIX PAR RAPPORT AU KIJUN (support/résistance)
   // ----------------------------------------------------------------
   // Karen Péloille: le Kijun est le support/résistance clé
   double kijunDist = MathAbs(currentPrice - ich.kijun);
   double kijunDistPct = (ich.kijun > 0) ? kijunDist / ich.kijun * 100 : 0;
   
   if(kijunDistPct < 0.1) // Prix très proche du Kijun
      AddToArray(warnings, "Prix très proche du Kijun (" + DoubleToString(kijunDistPct, 2) + "%) - zone de décision");
   
   WriteLog("  C7 - Distance au Kijun: " + DoubleToString(kijunDistPct, 3) + "%");
   
   // ----------------------------------------------------------------
   // CRITÈRE 8: ÉPAISSEUR DU KUMO (résistance/support du nuage)
   // ----------------------------------------------------------------
   double kijunValue = ich.kijun > 0 ? ich.kijun : 1;
   double kumoThicknessPct = (kijunValue > 0) ? kumoThickness / kijunValue * 100 : 0;
   
   if(kumoThicknessPct > 3.0)
      AddToArray(warnings, "Kumo épais (" + DoubleToString(kumoThicknessPct, 2) + "%) - traversée difficile");
   
   WriteLog("  C8 - Épaisseur Kumo: " + DoubleToString(kumoThicknessPct, 3) + "% | " +
            DoubleToString(kumoThickness / SymbolInfoDouble(symbol, SYMBOL_POINT), 0) + " points");
   
   // ================================================================
   // SYNTHÈSE ET SETUP DE TRADING
   // ================================================================
   
   string synthesis = "\n  SYNTHÈSE [" + tfName + "] " + symbol + ":\n";
   synthesis += "  Score BULL: " + IntegerToString(bullScore) + 
                " | Score BEAR: " + IntegerToString(bearScore) + "\n";
   
   // Direction dominante
   string direction = "";
   int    totalScore = 0;
   bool   setupValid = false;
   
   if(bullScore >= 6 && bullScore > bearScore + 2)
   {
      direction  = "BUY";
      totalScore = bullScore;
      setupValid = true;
      synthesis += "  >> SETUP HAUSSIER (score " + IntegerToString(bullScore) + "/11)\n";
   }
   else if(bearScore >= 6 && bearScore > bullScore + 2)
   {
      direction  = "SELL";
      totalScore = bearScore;
      setupValid = true;
      synthesis += "  >> SETUP BAISSIER (score " + IntegerToString(bearScore) + "/11)\n";
   }
   else
   {
      synthesis += "  >> PAS DE SETUP (scores insuffisants ou contradictoires)\n";
   }
   
   // Raisons
   if(direction == "BUY")
   {
      synthesis += "  Raisons haussières:\n";
      for(int r = 0; r < ArraySize(bullReasons); r++)
         synthesis += "    + " + bullReasons[r] + "\n";
   }
   else if(direction == "SELL")
   {
      synthesis += "  Raisons baissières:\n";
      for(int r = 0; r < ArraySize(bearReasons); r++)
         synthesis += "    - " + bearReasons[r] + "\n";
   }
   
   if(ArraySize(warnings) > 0)
   {
      synthesis += "  Alertes:\n";
      for(int w = 0; w < ArraySize(warnings); w++)
         synthesis += "    ! " + warnings[w] + "\n";
   }
   
   // Calcul SL, TP, Lots
   if(setupValid)
   {
      double entryPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(direction == "SELL") entryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
      
      double sl = 0, tp = 0;
      CalculateSLTP(symbol, tf, direction, ich, currentPrice, high, low, sl, tp);
      
      double lotSize = CalculateLotSize(symbol, entryPrice, sl);
      
      synthesis += "\n  TRADE PROPOSÉ:\n";
      synthesis += "  Direction: " + direction + "\n";
      synthesis += "  Entrée:    " + DoubleToString(entryPrice, _Digits) + "\n";
      synthesis += "  Stop Loss: " + DoubleToString(sl, _Digits) + "\n";
      synthesis += "  Take Profit: " + DoubleToString(tp, _Digits) + "\n";
      synthesis += "  Lots:      " + DoubleToString(lotSize, 2) + "\n";
      
      double slPips = MathAbs(entryPrice - sl) / SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tpPips = MathAbs(tp - entryPrice) / SymbolInfoDouble(symbol, SYMBOL_POINT);
      synthesis += "  SL: " + DoubleToString(slPips, 0) + " pts | TP: " + DoubleToString(tpPips, 0) + " pts | R/R: 1:" + DoubleToString(tpPips/MathMax(slPips,1), 2) + "\n";
      
      // Remplissage structure setup
      setup.symbol     = symbol;
      setup.timeframe  = tf;
      setup.direction  = direction;
      setup.entryPrice = entryPrice;
      setup.stopLoss   = sl;
      setup.takeProfit = tp;
      setup.lotSize    = lotSize;
      setup.score      = totalScore;
      setup.isValid    = true;
      
      // Copie des raisons
      if(direction == "BUY")
      {
         ArrayResize(setup.reasons, ArraySize(bullReasons));
         for(int r = 0; r < ArraySize(bullReasons); r++) setup.reasons[r] = bullReasons[r];
      }
      else
      {
         ArrayResize(setup.reasons, ArraySize(bearReasons));
         for(int r = 0; r < ArraySize(bearReasons); r++) setup.reasons[r] = bearReasons[r];
      }
      ArrayResize(setup.warnings, ArraySize(warnings));
      for(int w = 0; w < ArraySize(warnings); w++) setup.warnings[w] = warnings[w];
   }
   else
   {
      setup.isValid = false;
   }
   
   WriteLog(synthesis);
   return true;
}

//+------------------------------------------------------------------+
//| Calcul Stop Loss et Take Profit selon méthode KP                |
//+------------------------------------------------------------------+
void CalculateSLTP(const string symbol, const ENUM_TIMEFRAMES tf, 
                    const string direction, const IchimokuValues &ich,
                    const double currentPrice, const double &high[], const double &low[],
                    double &sl, double &tp)
{
   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   // Distance SL minimale = max(stops broker, 0.1% du prix)
   // Permet d'avoir un SL réaliste même sur des actifs à faible volatilité
   double entryBuy  = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double entryBid  = SymbolInfoDouble(symbol, SYMBOL_BID);
   long   stopsLvl  = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist   = MathMax((double)stopsLvl * point + spread,
                              entryBuy * 0.001); // au moins 0.1% du prix
   
   // Méthode Karen Péloille:
   // SL: de l'autre côté du Kijun (support/résistance clé) ou du Kumo
   // Le Kijun est le niveau de référence principal selon KP
   
   if(direction == "BUY")
   {
      double entryPrice = entryBuy;
      
      // Candidats SL selon KP:
      // 1. Sous le Kijun (support dynamique principal)
      // 2. Sous le bas du Kumo (si prix dans/sous le kumo)
      // 3. Sous le Tenkan (SL serré pour entrées précises)
      double slKijun  = ich.kijun  - spread - point;
      double slKumo   = MathMin(ich.senkouA, ich.senkouB) - spread - point;
      double slTenkan = ich.tenkan - spread - point;
      
      // Choix du SL selon la position du prix
      if(currentPrice > MathMax(ich.senkouA, ich.senkouB))
      {
         // Prix au-dessus du Kumo : SL sous le Kijun (méthode KP standard)
         sl = slKijun;
         // Si le Kijun est trop proche ou au-dessus du prix, utiliser le Kumo
         if(entryPrice - sl < minDist) sl = slKumo;
      }
      else
      {
         // Prix dans ou sous le Kumo : SL sous le Kumo
         sl = slKumo;
      }
      
      // Si le SL Ichimoku est trop proche (Kumo/Kijun plat), utiliser la volatilité récente
      if(entryPrice - sl < minDist)
      {
         double highestHigh = high[0], lowestLow = low[0];
         int lookback = MathMin(14, ArraySize(high)-1);
         for(int k = 1; k <= lookback; k++)
         {
            if(high[k] > highestHigh) highestHigh = high[k];
            if(low[k]  < lowestLow)  lowestLow  = low[k];
         }
         double atrProxy = (highestHigh - lowestLow) * 0.5;
         if(atrProxy > minDist) minDist = atrProxy;
         sl = entryPrice - minDist;
      }
      
      sl = MathMin(sl, entryPrice - minDist); // SL toujours en-dessous de l'entrée
      
      double slDistance = entryPrice - sl;
      
      // Sécurité: SL ne peut pas dépasser 20% du prix d'entrée
      double maxSlDistanceBuy = entryPrice * 0.20;
      if(slDistance > maxSlDistanceBuy)
      {
         sl = entryPrice - maxSlDistanceBuy;
         slDistance = maxSlDistanceBuy;
         WriteLog("  [WARN] SL plafonné à 20% du prix (" + DoubleToString(sl, digits) + ")");
      }
      
      tp = entryPrice + slDistance * InpTPRatio;
      
      // TP ne doit pas rester collé dans le Kumo futur
      double futurKumoBottom = MathMin(ich.senkouA_fwd, ich.senkouB_fwd);
      double futurKumoTop    = MathMax(ich.senkouA_fwd, ich.senkouB_fwd);
      if(tp > futurKumoBottom && tp < futurKumoTop)
         tp = futurKumoTop + spread; // Sauter par-dessus le Kumo futur
   }
   else // SELL
   {
      double entryPrice = entryBid;
      
      double slKijun  = ich.kijun  + spread + point;
      double slKumo   = MathMax(ich.senkouA, ich.senkouB) + spread + point;
      
      if(currentPrice < MathMin(ich.senkouA, ich.senkouB))
         sl = slKijun;
      else
         sl = slKumo;
      
      // Si le SL Ichimoku est trop proche (Kumo/Kijun plat), utiliser le SL Kijun W1
      // ou à défaut une distance basée sur la volatilité récente (range des 14 dernières bougies)
      if(sl - entryPrice < minDist)
      {
         // Calcul range récent sur 14 bougies comme proxy ATR
         double highestHigh = high[0], lowestLow = low[0];
         int lookback = MathMin(14, ArraySize(high)-1);
         for(int k = 1; k <= lookback; k++)
         {
            if(high[k] > highestHigh) highestHigh = high[k];
            if(low[k]  < lowestLow)  lowestLow  = low[k];
         }
         double atrProxy = (highestHigh - lowestLow) * 0.5; // 50% du range récent
         if(atrProxy > minDist) minDist = atrProxy;
         sl = entryPrice + minDist;
      }
      
      sl = MathMax(sl, entryPrice + minDist);
      
      double slDistance = sl - entryPrice;
      
      // Sécurité: SL ne peut pas dépasser 20% du prix d'entrée (évite les SL absurdes sur W1)
      double maxSlDistance = entryPrice * 0.20;
      if(slDistance > maxSlDistance)
      {
         sl = entryPrice + maxSlDistance;
         slDistance = maxSlDistance;
         WriteLog("  [WARN] SL plafonné à 20% du prix (" + DoubleToString(sl, digits) + ")");
      }
      
      tp = entryPrice - slDistance * InpTPRatio;
      
      // Sécurité absolue: TP doit être positif et réaliste
      if(tp <= 0) tp = entryPrice * 0.5;
      
      double futurKumoBottom = MathMin(ich.senkouA_fwd, ich.senkouB_fwd);
      double futurKumoTop    = MathMax(ich.senkouA_fwd, ich.senkouB_fwd);
      if(tp > futurKumoBottom && tp < futurKumoTop)
         tp = futurKumoBottom - spread;
      if(tp <= 0) tp = entryPrice * 0.5; // dernier filet
   }
   
   // Normalisation
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
}

//+------------------------------------------------------------------+
//| Calcul de la taille de lot (risque fixe 1%)                     |
//+------------------------------------------------------------------+
double CalculateLotSize(const string symbol, const double entryPrice, const double sl)
{
   double balance    = g_accountInfo.Balance();
   double riskAmount = balance * InpRiskPercent / 100.0;
   double point      = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tickValue  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot     = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot     = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   
   if(tickSize <= 0 || tickValue <= 0) return minLot;
   
   double slPoints     = MathAbs(entryPrice - sl) / tickSize;
   double valuePerLot  = slPoints * tickValue;
   
   if(valuePerLot <= 0) return minLot;
   
   double lots = riskAmount / valuePerLot;
   
   // Normalisation
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Résumé global des setups trouvés                                |
//+------------------------------------------------------------------+
void WriteSummary(TradeSetup &setups[], string &labels[], const int count)
{
   string summary = "\n" + StringRepeat("=", 70) + "\n";
   summary += "  RÉSUMÉ - " + IntegerToString(count) + " SETUP(S) IDENTIFIÉ(S)\n";
   summary += "  " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\n";
   summary += StringRepeat("=", 70) + "\n";
   
   if(count == 0)
   {
      summary += "  Aucun setup valide détecté sur l'ensemble des actifs analysés.\n";
      summary += "  Conseil: Rester en dehors du marché, attendre une configuration claire.\n";
   }
   else
   {
      double totalRisk = count * InpRiskPercent;
      summary += "  Risque total si tous les setups sont pris: " + 
                 DoubleToString(totalRisk, 1) + "% du capital\n";
      summary += "  Capital à risque: " + 
                 DoubleToString(g_accountInfo.Balance() * totalRisk / 100, 2) + 
                 " " + g_accountInfo.Currency() + "\n\n";
      
      for(int i = 0; i < ArraySize(setups); i++)
      {
         TradeSetup s = setups[i];
         summary += "  [" + IntegerToString(i+1) + "] " + labels[i] + "\n";
         summary += "      " + s.direction + " | Entrée: " + 
                    DoubleToString(s.entryPrice, _Digits) + "\n";
         summary += "      SL: " + DoubleToString(s.stopLoss, _Digits) + 
                    " | TP: " + DoubleToString(s.takeProfit, _Digits) + "\n";
         summary += "      Lots: " + DoubleToString(s.lotSize, 2) + 
                    " | Score: " + IntegerToString(s.score) + "/11\n";
         
         // Conseil de trading personnalisé
         summary += "      CONSEIL: " + GetTradingAdvice(s) + "\n\n";
      }
      
      // Conseil global
      summary += "  CONSEIL GLOBAL:\n";
      if(totalRisk > 5.0)
         summary += "  ATTENTION: Risque total élevé (" + DoubleToString(totalRisk, 1) + 
                    "%). Sélectionner les setups avec les meilleurs scores.\n";
      else
         summary += "  Risque total acceptable. Respecter la gestion du risque.\n";
   }
   
   summary += StringRepeat("=", 70);
   WriteLog(summary);
}

//+------------------------------------------------------------------+
//| Génération conseil de trading personnalisé                      |
//+------------------------------------------------------------------+
string GetTradingAdvice(const TradeSetup &s)
{
   string advice = "";
   
   if(s.score >= 9)
      advice = "SIGNAL TRÈS FORT - Configuration Ichimoku idéale selon méthode KP. ";
   else if(s.score >= 7)
      advice = "SIGNAL FORT - Bonne configuration Ichimoku. ";
   else
      advice = "SIGNAL MODÉRÉ - Configuration acceptable. ";
   
   if(s.direction == "BUY")
   {
      advice += "Acheter sur retour au Kijun si possible. ";
      advice += "Surveiller la tenue du support Kijun après entrée.";
   }
   else
   {
      advice += "Vendre sur rebond au Kijun si possible. ";
      advice += "Surveiller la résistance Kijun après entrée.";
   }
   
   if(ArraySize(s.warnings) > 0)
   {
      advice += " VIGILANCE: ";
      for(int w = 0; w < ArraySize(s.warnings); w++)
      {
         advice += s.warnings[w];
         if(w < ArraySize(s.warnings) - 1) advice += "; ";
      }
   }
   
   return advice;
}

//+------------------------------------------------------------------+
//| Exécution des trades en mode automatique                        |
//+------------------------------------------------------------------+
void ExecuteSetups(TradeSetup &setups[], string &labels[])
{
   int existingPositions = CountOpenPositions();
   
   WriteLog("\n[EXECUTION] Mode auto - " + IntegerToString(ArraySize(setups)) + " setups à évaluer");
   WriteLog("[EXECUTION] Positions existantes: " + IntegerToString(existingPositions));
   
   for(int i = 0; i < ArraySize(setups); i++)
   {
      if(existingPositions >= InpMaxPositions)
      {
         WriteLog("[EXECUTION] Limite de positions atteinte (" + IntegerToString(InpMaxPositions) + ")");
         break;
      }
      
      TradeSetup s = setups[i];
      
      // Vérifier si déjà en position sur ce symbole
      if(HasOpenPosition(s.symbol))
      {
         WriteLog("[EXECUTION] Position déjà ouverte sur " + s.symbol + " - ignoré");
         continue;
      }
      
      // Exécution
      bool success = false;
      if(s.direction == "BUY")
         success = g_trade.Buy(s.lotSize, s.symbol, s.entryPrice, s.stopLoss, s.takeProfit, 
                               "IchimokuKP|Score:" + IntegerToString(s.score));
      else
         success = g_trade.Sell(s.lotSize, s.symbol, s.entryPrice, s.stopLoss, s.takeProfit,
                                "IchimokuKP|Score:" + IntegerToString(s.score));
      
      string execLog = "[EXECUTION] " + s.direction + " " + s.symbol + " " + labels[i] + ": ";
      execLog += success ? "SUCCÈS (ticket #" + IntegerToString((int)g_trade.ResultOrder()) + ")" 
                         : "ÉCHEC (" + g_trade.ResultRetcodeDescription() + ")";
      WriteLog(execLog);
      
      if(success) existingPositions++;
   }
}

//+------------------------------------------------------------------+
//| Compter positions ouvertes par cet EA                           |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
         if(g_posInfo.Magic() == InpMagicNumber) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Vérifier si position ouverte sur un symbole                     |
//+------------------------------------------------------------------+
bool HasOpenPosition(const string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
         if(g_posInfo.Magic() == InpMagicNumber && g_posInfo.Symbol() == symbol)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Construction de la liste des timeframes actifs                  |
//+------------------------------------------------------------------+
void BuildTimeframeList()
{
   ArrayResize(g_timeframes, 0);
   ArrayResize(g_tfNames, 0);
   
   struct TFEntry { ENUM_TIMEFRAMES tf; string name; bool active; };
   TFEntry entries[] = {
      {PERIOD_M1,  "M1",  InpTradeM1},
      {PERIOD_M5,  "M5",  InpTradeM5},
      {PERIOD_M15, "M15", InpTradeM15},
      {PERIOD_M30, "M30", InpTradeM30},
      {PERIOD_H1,  "H1",  InpTradeH1},
      {PERIOD_H4,  "H4",  InpTradeH4},
      {PERIOD_D1,  "D1",  InpTradeD1},
      {PERIOD_W1,  "W1",  InpTradeW1},
      {PERIOD_MN1, "MN",  InpTradeMN}
   };
   
   for(int i = 0; i < ArraySize(entries); i++)
   {
      if(entries[i].active)
      {
         int sz = ArraySize(g_timeframes);
         ArrayResize(g_timeframes, sz + 1);
         ArrayResize(g_tfNames,    sz + 1);
         g_timeframes[sz] = entries[i].tf;
         g_tfNames[sz]    = entries[i].name;
      }
   }
   
   WriteLog("Timeframes actifs: " + IntegerToString(ArraySize(g_timeframes)));
}

//+------------------------------------------------------------------+
//| Ajout d'un élément à un tableau de strings                      |
//+------------------------------------------------------------------+
void AddToArray(string &arr[], const string value)
{
   int sz = ArraySize(arr);
   ArrayResize(arr, sz + 1);
   arr[sz] = value;
}

//+------------------------------------------------------------------+
//| Écriture dans le fichier de log                                 |
//+------------------------------------------------------------------+
void WriteLog(const string message)
{
   // Affichage console
   Print(message);
   
   // Ouverture du fichier (mode append)
   int handle = FileOpen(g_logPath, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   
   if(handle == INVALID_HANDLE)
   {
      // Essai en création
      handle = FileOpen(g_logPath, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   }
   
   if(handle != INVALID_HANDLE)
   {
      // Aller à la fin du fichier
      FileSeek(handle, 0, SEEK_END);
      FileWriteString(handle, message + "\n");
      FileClose(handle); // Fermeture immédiate après écriture
   }
   else
   {
      Print("[LOG ERROR] Impossible d'ouvrir le fichier: ", g_logPath, " Erreur: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Répétition d'une chaîne                                         |
//+------------------------------------------------------------------+
string StringRepeat(const string s, const int count)
{
   string result = "";
   for(int i = 0; i < count; i++) result += s;
   return result;
}

//+------------------------------------------------------------------+
//| Événement de fin de barre (optionnel - analyse sur nouvelle bougie)|
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Bouton de déclenchement manuel possible via graphique
   if(id == CHARTEVENT_KEYDOWN && lparam == 'A')
   {
      WriteLog("\n[MANUEL] Analyse déclenchée manuellement par l'utilisateur");
      RunFullAnalysis();
   }
}
//+------------------------------------------------------------------+
