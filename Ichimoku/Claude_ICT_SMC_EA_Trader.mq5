//+------------------------------------------------------------------+
//|          ICT / SMC MULTI-TIMEFRAME EXPERT ADVISOR                |
//|          FVG · Order Block · MSS · PDH/PDL · PWH/PWL             |
//|          Multi-TF : M1 · M5 · M15  |  Risk 1% · RR ≥ 1:2        |
//|          Version 1.00  –  Compatible tout actif                  |
//+------------------------------------------------------------------+
#property version   "1.00"
#property copyright "ICT SMC EA by Didier Le HPI Réunionnais 2026"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//|  PARAMÈTRES D'ENTRÉE                                             |
//+------------------------------------------------------------------+

// --- Gestion du risque ---
input double   RiskPercent        = 1.0;    // Risque par trade (% du solde)
input double   MinRR              = 2.0;    // Ratio Risque/Récompense minimum
input int      Slippage           = 20;     // Slippage en points
input int      MaxSpread          = 80;     // Spread max autorisé (points)
input ulong    MagicNumber        = 20250420;

// --- Paramètres ICT/SMC ---
input int      SwingLookback      = 10;     // Bougies pour détecter swing H/L
input int      OB_Lookback        = 20;     // Bougies lookback pour Order Blocks
input int      FVG_MinPoints      = 5;      // Taille minimale FVG (en points)
input int      MSS_Lookback       = 15;     // Bougies lookback pour MSS
input bool     RequireFVG         = true;   // Exiger une FVG pour entrer
input bool     RequireOB          = true;   // Exiger un Order Block pour entrer
input bool     RequireMSS         = true;   // Exiger un MSS pour entrer

// --- Filtres de contexte ---
input bool     UseM15Filter       = true;   // Utiliser M15 comme filtre HTF
input bool     UseM5Filter        = true;   // Utiliser M5 comme filtre MTF
input bool     UseM1Entry         = true;   // Utiliser M1 pour l'entrée précise
input bool     UsePDLevels        = true;   // Utiliser PDH/PDL/PWH/PWL
input bool     UseAsianSession    = false;  // Ignorer session asiatique (forex)
input int      AsianSessionEnd    = 8;      // Heure fin session asiatique (GMT)

// --- Trailing / Breakeven ---
input bool     UseBreakeven       = true;
input int      BreakevenPips      = 30;
input bool     UseTrailing        = true;
input int      TrailingStart      = 40;
input int      TrailingStep       = 20;

// --- Affichage ---
input bool     ShowDashboard      = true;
input bool     DebugMode          = false;

//+------------------------------------------------------------------+
//|  STRUCTURES                                                      |
//+------------------------------------------------------------------+

struct SwingPoint
  {
   double   price;
   datetime time;
   bool     valid;
  };

struct FVG
  {
   double   top;
   double   bottom;
   datetime time;
   int      direction; // 1=bullish, -1=bearish
   bool     valid;
  };

struct OrderBlock
  {
   double   high;
   double   low;
   datetime time;
   int      direction; // 1=bull OB, -1=bear OB
   bool     valid;
   bool     mitigated;
  };

struct PDLevels
  {
   double   pdh;   // Previous Day High
   double   pdl;   // Previous Day Low
   double   pwh;   // Previous Week High
   double   pwl;   // Previous Week Low
   double   pdm;   // Previous Day Midpoint (50%)
   datetime calculated;
  };

struct MarketBias
  {
   int      m15bias;   // 1=bullish, -1=bearish, 0=neutral
   int      m5bias;
   int      m1bias;
   int      overall;   // consensus
  };

//+------------------------------------------------------------------+
//|  VARIABLES GLOBALES                                              |
//+------------------------------------------------------------------+

// Derniers niveaux calculés
PDLevels  g_pd;
MarketBias g_bias;

// Historique des swings sur chaque TF
SwingPoint g_swingHighM15[], g_swingLowM15[];
SwingPoint g_swingHighM5[],  g_swingLowM5[];
SwingPoint g_swingHighM1[],  g_swingLowM1[];

// Order Blocks
OrderBlock g_obBullM15, g_obBearM15;
OrderBlock g_obBullM5,  g_obBearM5;
OrderBlock g_obBullM1,  g_obBearM1;

// FVG actives
FVG g_fvgBullM5, g_fvgBearM5;
FVG g_fvgBullM1, g_fvgBearM1;

// MSS
bool g_mssBull = false, g_mssBear = false;
datetime g_mssTime;

// Contrôle de fréquence
datetime g_lastAnalysis = 0;
int      g_analysisInterval = 30; // secondes entre analyses

// Symbole info
double g_point;
int    g_digits;
double g_tickSize;
double g_tickValue;

//+------------------------------------------------------------------+
//|  INITIALISATION                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_tickValue= SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(g_point == 0 || g_tickSize == 0 || g_tickValue == 0)
     {
      Print("ERREUR: Impossible d'obtenir les infos symbole pour ", _Symbol);
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);

   // Tenter ORDER_FILLING_FOK, sinon IOC
   ENUM_ORDER_TYPE_FILLING filling = (ENUM_ORDER_TYPE_FILLING)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      trade.SetTypeFilling(ORDER_FILLING_IOC);

   Print("=== ICT SMC EA démarré ===");
   Print("Symbole: ", _Symbol, " | Point: ", g_point, " | Digits: ", g_digits);
   Print("Risk: ", RiskPercent, "% | Min R:R: 1:", MinRR);

   // Analyse initiale
   UpdateAllLevels();

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Comment("");
   Print("ICT SMC EA arrêté. Raison: ", reason);
  }

//+------------------------------------------------------------------+
//|  TICK PRINCIPAL                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Gestion des positions ouvertes (BE + trailing)
   ManageOpenPositions();

   // Limiter la fréquence d'analyse
   if(TimeCurrent() - g_lastAnalysis < g_analysisInterval) return;
   g_lastAnalysis = TimeCurrent();

   // Vérification de base
   if(!IsTradeAllowed()) return;
   if(IsSpreadTooHigh()) return;

   // Mettre à jour tous les niveaux
   UpdateAllLevels();

   // Afficher le tableau de bord
   if(ShowDashboard) DrawDashboard();

   // Si une position est déjà ouverte, pas de nouvel ordre
   if(HasOpenPosition()) return;

   // Filtre session (optionnel)
   if(UseAsianSession && IsAsianSession()) return;

   // === LOGIQUE DE TRADE ===
   CheckAndTrade();
  }

//+------------------------------------------------------------------+
//|  MISE À JOUR DE TOUS LES NIVEAUX ICT                            |
//+------------------------------------------------------------------+
void UpdateAllLevels()
  {
   // 1) PD Levels (PDH, PDL, PWH, PWL)
   if(UsePDLevels) CalculatePDLevels();

   // 2) Swings sur chaque TF
   DetectSwings(PERIOD_M15, g_swingHighM15, g_swingLowM15);
   DetectSwings(PERIOD_M5,  g_swingHighM5,  g_swingLowM5);
   DetectSwings(PERIOD_M1,  g_swingHighM1,  g_swingLowM1);

   // 3) Biais de marché (MSS)
   g_bias.m15bias = GetMarketBias(PERIOD_M15, g_swingHighM15, g_swingLowM15);
   g_bias.m5bias  = GetMarketBias(PERIOD_M5,  g_swingHighM5,  g_swingLowM5);
   g_bias.m1bias  = GetMarketBias(PERIOD_M1,  g_swingHighM1,  g_swingLowM1);
   g_bias.overall = GetOverallBias();

   // 4) Order Blocks
   g_obBullM15 = FindLastBullOB(PERIOD_M15);
   g_obBearM15 = FindLastBearOB(PERIOD_M15);
   g_obBullM5  = FindLastBullOB(PERIOD_M5);
   g_obBearM5  = FindLastBearOB(PERIOD_M5);
   g_obBullM1  = FindLastBullOB(PERIOD_M1);
   g_obBearM1  = FindLastBearOB(PERIOD_M1);

   // 5) FVG (Fair Value Gaps)
   g_fvgBullM5 = FindLastFVG(PERIOD_M5,  1);
   g_fvgBearM5 = FindLastFVG(PERIOD_M5, -1);
   g_fvgBullM1 = FindLastFVG(PERIOD_M1,  1);
   g_fvgBearM1 = FindLastFVG(PERIOD_M1, -1);

   // 6) Market Structure Shift
   DetectMSS();
  }

//+------------------------------------------------------------------+
//|  CALCUL PDH / PDL / PWH / PWL                                   |
//+------------------------------------------------------------------+
void CalculatePDLevels()
  {
   MqlRates daily[], weekly[];
   ArraySetAsSeries(daily,  true);
   ArraySetAsSeries(weekly, true);

   // Daily
   if(CopyRates(_Symbol, PERIOD_D1, 1, 2, daily) >= 2)
     {
      g_pd.pdh = daily[0].high;
      g_pd.pdl = daily[0].low;
      g_pd.pdm = (g_pd.pdh + g_pd.pdl) / 2.0;
     }

   // Weekly
   if(CopyRates(_Symbol, PERIOD_W1, 1, 2, weekly) >= 2)
     {
      g_pd.pwh = weekly[0].high;
      g_pd.pwl = weekly[0].low;
     }

   g_pd.calculated = TimeCurrent();
  }

//+------------------------------------------------------------------+
//|  DÉTECTION DES SWINGS HIGH / LOW                                |
//+------------------------------------------------------------------+
void DetectSwings(ENUM_TIMEFRAMES tf, SwingPoint &highs[], SwingPoint &lows[])
  {
   int count = SwingLookback * 3 + 5;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, tf, 0, count, r) < count) return;

   ArrayFree(highs); ArrayFree(lows);
   int hi = 0, li = 0;

   for(int i = SwingLookback; i < count - SwingLookback; i++)
     {
      bool isHigh = true, isLow = true;
      for(int j = 1; j <= SwingLookback; j++)
        {
         if(r[i].high <= r[i-j].high || r[i].high <= r[i+j].high) isHigh = false;
         if(r[i].low  >= r[i-j].low  || r[i].low  >= r[i+j].low)  isLow  = false;
        }
      if(isHigh)
        {
         ArrayResize(highs, hi + 1);
         highs[hi].price = r[i].high;
         highs[hi].time  = r[i].time;
         highs[hi].valid = true;
         hi++;
        }
      if(isLow)
        {
         ArrayResize(lows, li + 1);
         lows[li].price = r[i].low;
         lows[li].time  = r[i].time;
         lows[li].valid = true;
         li++;
        }
     }
  }

//+------------------------------------------------------------------+
//|  BIAIS DE MARCHÉ (Higher Highs/Higher Lows ou LH/LL)            |
//+------------------------------------------------------------------+
int GetMarketBias(ENUM_TIMEFRAMES tf, SwingPoint &highs[], SwingPoint &lows[])
  {
   int nh = ArraySize(highs), nl = ArraySize(lows);
   if(nh < 2 || nl < 2) return 0;

   bool hh = highs[0].price > highs[1].price; // Higher High
   bool hl = lows[0].price  > lows[1].price;  // Higher Low
   bool lh = highs[0].price < highs[1].price; // Lower High
   bool ll = lows[0].price  < lows[1].price;  // Lower Low

   if(hh && hl) return  1; // Bullish structure
   if(lh && ll) return -1; // Bearish structure
   return 0;
  }

//+------------------------------------------------------------------+
//|  BIAIS GLOBAL (consensus des 3 TF)                              |
//+------------------------------------------------------------------+
int GetOverallBias()
  {
   int score = 0;
   if(UseM15Filter) score += g_bias.m15bias * 2; // M15 a plus de poids
   if(UseM5Filter)  score += g_bias.m5bias;
   if(UseM1Entry)   score += g_bias.m1bias;

   if(score > 0) return  1;
   if(score < 0) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//|  DÉTECTION DU DERNIER ORDER BLOCK BULLISH                       |
//|  Définition ICT: Dernière bougie bearish avant un move up fort   |
//+------------------------------------------------------------------+
OrderBlock FindLastBullOB(ENUM_TIMEFRAMES tf)
  {
   OrderBlock ob;
   ob.valid = false;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int count = OB_Lookback + 5;
   if(CopyRates(_Symbol, tf, 0, count, r) < count) return ob;

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = 2; i < count - 2; i++)
     {
      // Chercher une bougie bearish suivie d'un mouvement haussier fort
      bool bearCandle = (r[i].close < r[i].open);
      if(!bearCandle) continue;

      // Le move suivant doit être haussier et fort
      double moveUp = 0;
      for(int j = i - 1; j >= MathMax(0, i - 4); j--)
         moveUp += (r[j].close - r[j].open);

      if(moveUp <= 0) continue;

      // La bougie OB doit être en-dessous du prix actuel (pour un trade long)
      if(r[i].high >= currentPrice) continue;

      // Vérifier que le prix n'a pas encore retouché cette zone
      bool mitigated = false;
      for(int j = i - 1; j >= 1; j--)
        {
         if(r[j].low <= r[i].high && r[j].high >= r[i].low)
           { mitigated = true; break; }
        }

      ob.high      = r[i].high;
      ob.low       = r[i].low;
      ob.time      = r[i].time;
      ob.direction = 1;
      ob.valid     = true;
      ob.mitigated = mitigated;
      return ob;
     }
   return ob;
  }

//+------------------------------------------------------------------+
//|  DÉTECTION DU DERNIER ORDER BLOCK BEARISH                       |
//+------------------------------------------------------------------+
OrderBlock FindLastBearOB(ENUM_TIMEFRAMES tf)
  {
   OrderBlock ob;
   ob.valid = false;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int count = OB_Lookback + 5;
   if(CopyRates(_Symbol, tf, 0, count, r) < count) return ob;

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = 2; i < count - 2; i++)
     {
      bool bullCandle = (r[i].close > r[i].open);
      if(!bullCandle) continue;

      double moveDown = 0;
      for(int j = i - 1; j >= MathMax(0, i - 4); j--)
         moveDown += (r[j].open - r[j].close);

      if(moveDown <= 0) continue;

      // L'OB bearish doit être au-dessus du prix actuel
      if(r[i].low <= currentPrice) continue;

      bool mitigated = false;
      for(int j = i - 1; j >= 1; j--)
        {
         if(r[j].high >= r[i].low && r[j].low <= r[i].high)
           { mitigated = true; break; }
        }

      ob.high      = r[i].high;
      ob.low       = r[i].low;
      ob.time      = r[i].time;
      ob.direction = -1;
      ob.valid     = true;
      ob.mitigated = mitigated;
      return ob;
     }
   return ob;
  }

//+------------------------------------------------------------------+
//|  DÉTECTION FVG (Fair Value Gap / Imbalance)                     |
//|  FVG Bullish : Low[i] > High[i+2]  (gap haussier)              |
//|  FVG Bearish : High[i] < Low[i+2]  (gap baissier)              |
//+------------------------------------------------------------------+
FVG FindLastFVG(ENUM_TIMEFRAMES tf, int direction)
  {
   FVG fvg;
   fvg.valid = false;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int count = OB_Lookback + 5;
   if(CopyRates(_Symbol, tf, 0, count, r) < count) return fvg;

   double minSize = FVG_MinPoints * g_point;
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = 1; i < count - 2; i++)
     {
      if(direction == 1)
        {
         // FVG Bullish: candle[i+2].high < candle[i].low
         double gapSize = r[i].low - r[i+2].high;
         if(gapSize < minSize) continue;
         // Le FVG doit être en-dessous du prix actuel
         if(r[i].low >= currentPrice) continue;
         fvg.top       = r[i].low;
         fvg.bottom    = r[i+2].high;
         fvg.time      = r[i].time;
         fvg.direction = 1;
         fvg.valid     = true;
         return fvg;
        }
      else
        {
         // FVG Bearish: candle[i+2].low > candle[i].high
         double gapSize = r[i+2].low - r[i].high;
         if(gapSize < minSize) continue;
         // Le FVG doit être au-dessus du prix actuel
         if(r[i].high <= currentPrice) continue;
         fvg.top       = r[i+2].low;
         fvg.bottom    = r[i].high;
         fvg.time      = r[i].time;
         fvg.direction = -1;
         fvg.valid     = true;
         return fvg;
        }
     }
   return fvg;
  }

//+------------------------------------------------------------------+
//|  DÉTECTION MSS (Market Structure Shift)                         |
//|  MSS Bullish : Prix casse un swing high précédent (bearish → bullish) |
//|  MSS Bearish : Prix casse un swing low précédent                |
//+------------------------------------------------------------------+
void DetectMSS()
  {
   g_mssBull = false;
   g_mssBear = false;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int count = MSS_Lookback + 5;
   if(CopyRates(_Symbol, PERIOD_M5, 0, count, r) < count) return;

   double currentClose = r[0].close;

   // Chercher le dernier swing high sur M5
   int nh = ArraySize(g_swingHighM5);
   int nl = ArraySize(g_swingLowM5);

   if(nh >= 2 && nl >= 2)
     {
      // MSS Bullish: le prix vient de casser le dernier swing high (contexte était baissier)
      if(g_bias.m5bias == -1 || g_bias.m5bias == 0)
        {
         double lastSwingHigh = g_swingHighM5[0].price;
         if(currentClose > lastSwingHigh && r[1].close <= lastSwingHigh)
           {
            g_mssBull = true;
            g_mssTime = r[0].time;
            if(DebugMode) Print("MSS Bullish détecté sur M5 @ ", currentClose);
           }
        }

      // MSS Bearish: le prix vient de casser le dernier swing low
      if(g_bias.m5bias == 1 || g_bias.m5bias == 0)
        {
         double lastSwingLow = g_swingLowM5[0].price;
         if(currentClose < lastSwingLow && r[1].close >= lastSwingLow)
           {
            g_mssBear = true;
            g_mssTime = r[0].time;
            if(DebugMode) Print("MSS Bearish détecté sur M5 @ ", currentClose);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|  LOGIQUE PRINCIPALE : CHERCHER UN SETUP LONG OU SHORT           |
//+------------------------------------------------------------------+
void CheckAndTrade()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // === SETUP LONG ===
   if(CheckLongSetup())
     {
      double entry, sl, tp;
      if(CalculateLongLevels(ask, entry, sl, tp))
        {
         double rr = MathAbs(tp - entry) / MathAbs(entry - sl);
         if(rr >= MinRR)
           {
            double lot = CalculateLots(entry, sl);
            if(lot > 0)
              {
               if(DebugMode) Print("LONG Setup: Entry=", entry, " SL=", sl, " TP=", tp, " RR=", NormalizeDouble(rr,2), " Lots=", lot);
               ExecuteLong(entry, sl, tp, lot);
              }
           }
         else if(DebugMode)
            Print("LONG Setup rejeté: RR=", NormalizeDouble(rr,2), " < ", MinRR);
        }
     }

   // === SETUP SHORT ===
   else if(CheckShortSetup())
     {
      double entry, sl, tp;
      if(CalculateShortLevels(bid, entry, sl, tp))
        {
         double rr = MathAbs(entry - tp) / MathAbs(sl - entry);
         if(rr >= MinRR)
           {
            double lot = CalculateLots(entry, sl);
            if(lot > 0)
              {
               if(DebugMode) Print("SHORT Setup: Entry=", entry, " SL=", sl, " TP=", tp, " RR=", NormalizeDouble(rr,2), " Lots=", lot);
               ExecuteShort(entry, sl, tp, lot);
              }
           }
         else if(DebugMode)
            Print("SHORT Setup rejeté: RR=", NormalizeDouble(rr,2), " < ", MinRR);
        }
     }
  }

//+------------------------------------------------------------------+
//|  VALIDATION SETUP LONG                                          |
//|  Conditions: biais haussier + OB bull + FVG bull + MSS bull     |
//+------------------------------------------------------------------+
bool CheckLongSetup()
  {
   // 1) Biais HTF haussier (M15 obligatoire si filtre activé)
   if(UseM15Filter && g_bias.m15bias != 1) return false;
   if(UseM5Filter  && g_bias.m5bias  == -1) return false;

   // 2) MSS Bullish (optionnel selon paramètre)
   if(RequireMSS && !g_mssBull) return false;

   // 3) Order Block bullish accessible
   if(RequireOB)
     {
      bool obFound = false;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // Vérifier OB sur M5 ou M1
      if(g_obBullM5.valid && !g_obBullM5.mitigated && ask >= g_obBullM5.low && ask <= g_obBullM5.high * 1.002)
         obFound = true;
      if(g_obBullM1.valid && !g_obBullM1.mitigated && ask >= g_obBullM1.low && ask <= g_obBullM1.high * 1.002)
         obFound = true;

      if(!obFound) return false;
     }

   // 4) FVG Bullish accessible
   if(RequireFVG)
     {
      bool fvgFound = false;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(g_fvgBullM5.valid && ask >= g_fvgBullM5.bottom && ask <= g_fvgBullM5.top)
         fvgFound = true;
      if(g_fvgBullM1.valid && ask >= g_fvgBullM1.bottom && ask <= g_fvgBullM1.top)
         fvgFound = true;

      if(!fvgFound) return false;
     }

   // 5) Prix au-dessus du PDL (pas d'acheter sous le plancher daily)
   if(UsePDLevels && SymbolInfoDouble(_Symbol, SYMBOL_ASK) < g_pd.pdl) return false;

   return true;
  }

//+------------------------------------------------------------------+
//|  VALIDATION SETUP SHORT                                         |
//+------------------------------------------------------------------+
bool CheckShortSetup()
  {
   // 1) Biais HTF baissier
   if(UseM15Filter && g_bias.m15bias != -1) return false;
   if(UseM5Filter  && g_bias.m5bias  == 1)  return false;

   // 2) MSS Bearish
   if(RequireMSS && !g_mssBear) return false;

   // 3) Order Block bearish accessible
   if(RequireOB)
     {
      bool obFound = false;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(g_obBearM5.valid && !g_obBearM5.mitigated && bid <= g_obBearM5.high && bid >= g_obBearM5.low * 0.998)
         obFound = true;
      if(g_obBearM1.valid && !g_obBearM1.mitigated && bid <= g_obBearM1.high && bid >= g_obBearM1.low * 0.998)
         obFound = true;

      if(!obFound) return false;
     }

   // 4) FVG Bearish accessible
   if(RequireFVG)
     {
      bool fvgFound = false;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(g_fvgBearM5.valid && bid <= g_fvgBearM5.top && bid >= g_fvgBearM5.bottom)
         fvgFound = true;
      if(g_fvgBearM1.valid && bid <= g_fvgBearM1.top && bid >= g_fvgBearM1.bottom)
         fvgFound = true;

      if(!fvgFound) return false;
     }

   // 5) Prix en-dessous du PDH
   if(UsePDLevels && SymbolInfoDouble(_Symbol, SYMBOL_BID) > g_pd.pdh) return false;

   return true;
  }

//+------------------------------------------------------------------+
//|  CALCUL NIVEAUX LONG : Entry / SL / TP                         |
//+------------------------------------------------------------------+
bool CalculateLongLevels(double ask, double &entry, double &sl, double &tp)
  {
   entry = ask;

   // SL = sous le dernier swing low M1 ou M5 (le plus proche)
   sl = 0;
   int nl1 = ArraySize(g_swingLowM1);
   int nl5 = ArraySize(g_swingLowM5);

   if(nl1 > 0 && g_swingLowM1[0].price < ask)
      sl = g_swingLowM1[0].price - (5 * g_point); // 5 pts de buffer

   if(sl == 0 && nl5 > 0 && g_swingLowM5[0].price < ask)
      sl = g_swingLowM5[0].price - (5 * g_point);

   // Fallback: utiliser l'OB bullish comme SL
   if(sl == 0 && g_obBullM5.valid)
      sl = g_obBullM5.low - (5 * g_point);

   if(sl == 0 || sl >= entry) return false;

   double riskDist = entry - sl;

   // TP = vers le prochain swing high ou niveau de liquidité
   tp = 0;

   // Option 1: Prochain swing high M5
   int nh5 = ArraySize(g_swingHighM5);
   for(int i = 0; i < nh5; i++)
     {
      if(g_swingHighM5[i].price > entry + (riskDist * MinRR))
        {
         tp = g_swingHighM5[i].price;
         break;
        }
     }

   // Option 2: PDH ou PWH
   if(tp == 0 && UsePDLevels)
     {
      if(g_pd.pdh > entry + (riskDist * MinRR)) tp = g_pd.pdh - (2 * g_point);
      else if(g_pd.pwh > entry + (riskDist * MinRR)) tp = g_pd.pwh - (2 * g_point);
     }

   // Fallback: TP calculé avec MinRR
   if(tp == 0 || tp <= entry)
      tp = entry + (riskDist * MinRR);

   // Validation finale
   double rr = (tp - entry) / (entry - sl);
   return (rr >= MinRR && sl > 0 && tp > entry);
  }

//+------------------------------------------------------------------+
//|  CALCUL NIVEAUX SHORT : Entry / SL / TP                        |
//+------------------------------------------------------------------+
bool CalculateShortLevels(double bid, double &entry, double &sl, double &tp)
  {
   entry = bid;

   // SL = au-dessus du dernier swing high M1 ou M5
   sl = 0;
   int nh1 = ArraySize(g_swingHighM1);
   int nh5 = ArraySize(g_swingHighM5);

   if(nh1 > 0 && g_swingHighM1[0].price > bid)
      sl = g_swingHighM1[0].price + (5 * g_point);

   if(sl == 0 && nh5 > 0 && g_swingHighM5[0].price > bid)
      sl = g_swingHighM5[0].price + (5 * g_point);

   if(sl == 0 && g_obBearM5.valid)
      sl = g_obBearM5.high + (5 * g_point);

   if(sl == 0 || sl <= entry) return false;

   double riskDist = sl - entry;

   // TP = vers le prochain swing low ou PDL/PWL
   tp = 0;

   int nl5 = ArraySize(g_swingLowM5);
   for(int i = 0; i < nl5; i++)
     {
      if(g_swingLowM5[i].price < entry - (riskDist * MinRR))
        {
         tp = g_swingLowM5[i].price;
         break;
        }
     }

   if(tp == 0 && UsePDLevels)
     {
      if(g_pd.pdl < entry - (riskDist * MinRR)) tp = g_pd.pdl + (2 * g_point);
      else if(g_pd.pwl < entry - (riskDist * MinRR)) tp = g_pd.pwl + (2 * g_point);
     }

   if(tp == 0 || tp >= entry)
      tp = entry - (riskDist * MinRR);

   double rr = (entry - tp) / (sl - entry);
   return (rr >= MinRR && sl > 0 && tp < entry);
  }

//+------------------------------------------------------------------+
//|  CALCUL DU NOMBRE DE LOTS (Risk 1% du solde)                   |
//+------------------------------------------------------------------+
double CalculateLots(double entry, double sl)
  {
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt   = balance * (RiskPercent / 100.0);
   double slDist    = MathAbs(entry - sl);

   if(slDist == 0) return 0;

   // Valeur monétaire du SL pour 1 lot
   double slValue = (slDist / g_tickSize) * g_tickValue;
   if(slValue == 0) return 0;

   double lots = riskAmt / slValue;

   // Arrondir au pas de lot
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, lotMin);
   lots = MathMin(lots, lotMax);

   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
//|  EXÉCUTION TRADE LONG                                           |
//+------------------------------------------------------------------+
bool ExecuteLong(double entry, double sl, double tp, double lot)
  {
   int    digits   = g_digits;
   long   stopLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Vérification niveaux stop
   if(stopLvl > 0)
     {
      double minDist = stopLvl * g_point;
      if(ask - sl < minDist) { Print("LONG: SL trop proche"); return false; }
      if(tp - ask < minDist) { Print("LONG: TP trop proche"); return false; }
     }

   if(trade.Buy(lot, _Symbol, ask, sl, tp, "ICT SMC LONG"))
     {
      ulong ticket = trade.ResultOrder();
      Print("✓ LONG exécuté | Ticket:", ticket, " Lot:", lot, " Entry:", ask, " SL:", sl, " TP:", tp);
      return true;
     }

   Print("✗ LONG échoué | Erreur:", GetLastError(), " Retcode:", trade.ResultRetcode());
   return false;
  }

//+------------------------------------------------------------------+
//|  EXÉCUTION TRADE SHORT                                          |
//+------------------------------------------------------------------+
bool ExecuteShort(double entry, double sl, double tp, double lot)
  {
   int    digits  = g_digits;
   long   stopLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   if(stopLvl > 0)
     {
      double minDist = stopLvl * g_point;
      if(sl - bid < minDist) { Print("SHORT: SL trop proche"); return false; }
      if(bid - tp < minDist) { Print("SHORT: TP trop proche"); return false; }
     }

   if(trade.Sell(lot, _Symbol, bid, sl, tp, "ICT SMC SHORT"))
     {
      ulong ticket = trade.ResultOrder();
      Print("✓ SHORT exécuté | Ticket:", ticket, " Lot:", lot, " Entry:", bid, " SL:", sl, " TP:", tp);
      return true;
     }

   Print("✗ SHORT échoué | Erreur:", GetLastError(), " Retcode:", trade.ResultRetcode());
   return false;
  }

//+------------------------------------------------------------------+
//|  GESTION POSITIONS : BREAKEVEN + TRAILING STOP                  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   double point  = g_point;
   int    digits = g_digits;
   long   stopLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)     continue;
      if(PositionGetInteger(POSITION_MAGIC)  != (long)MagicNumber) continue;

      double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl           = PositionGetDouble(POSITION_SL);
      double tp           = PositionGetDouble(POSITION_TP);
      long   type         = PositionGetInteger(POSITION_TYPE);

      double profitPts = (type == POSITION_TYPE_BUY)
                         ? (currentPrice - openPrice) / point
                         : (openPrice - currentPrice) / point;

      double newSL = sl;
      bool   changed = false;

      // --- Breakeven ---
      if(UseBreakeven && profitPts >= BreakevenPips)
        {
         double beSL = (type == POSITION_TYPE_BUY)
                       ? openPrice + 2 * point
                       : openPrice - 2 * point;
         beSL = NormalizeDouble(beSL, digits);

         if(type == POSITION_TYPE_BUY && (sl == 0 || beSL > sl))
            { newSL = beSL; changed = true; }
         else if(type == POSITION_TYPE_SELL && (sl == 0 || beSL < sl))
            { newSL = beSL; changed = true; }
        }

      // --- Trailing Stop ---
      if(UseTrailing && profitPts >= TrailingStart)
        {
         double trSL;
         if(type == POSITION_TYPE_BUY)
           {
            trSL = NormalizeDouble(currentPrice - TrailingStep * point, digits);
            if((sl == 0 || trSL > newSL) && (trSL <= currentPrice - stopLvl * point))
               { newSL = trSL; changed = true; }
           }
         else
           {
            trSL = NormalizeDouble(currentPrice + TrailingStep * point, digits);
            if((sl == 0 || trSL < newSL) && (trSL >= currentPrice + stopLvl * point))
               { newSL = trSL; changed = true; }
           }
        }

      // Appliquer si le SL a vraiment changé
      if(changed && MathAbs(newSL - sl) >= point)
        {
         trade.PositionModify(ticket, newSL, tp);
         if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
            Print("SL mis à jour ticket#", ticket, " → ", newSL);
        }
     }
  }

//+------------------------------------------------------------------+
//|  UTILITAIRES                                                    |
//+------------------------------------------------------------------+

bool IsTradeAllowed()
  {
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 1 &&
          MQLInfoInteger(MQL_TRADE_ALLOWED) == 1;
  }

bool IsSpreadTooHigh()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int spread = (int)MathRound((ask - bid) / g_point);
   if(spread > MaxSpread)
     {
      if(DebugMode) Print("Spread trop élevé: ", spread, " pts");
      return true;
     }
   return false;
  }

bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
            return true;
     }
   return false;
  }

bool IsAsianSession()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.hour < AsianSessionEnd);
  }

string BiasToString(int bias)
  {
   if(bias ==  1) return "HAUSSIER ▲";
   if(bias == -1) return "BAISSIER ▼";
   return "NEUTRE —";
  }

//+------------------------------------------------------------------+
//|  TABLEAU DE BORD (Comment)                                      |
//+------------------------------------------------------------------+
void DrawDashboard()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int spread = (int)MathRound((ask - bid) / g_point);

   string sep  = "─────────────────────────────\n";
   string dash = "╔══════ ICT SMC EA v1.00 ═════╗\n";

   dash += "║ " + _Symbol + " | " + TimeToString(TimeCurrent(), TIME_MINUTES) + "\n";
   dash += "║ Bid: " + DoubleToString(bid, g_digits) + "  Spread: " + IntegerToString(spread) + " pts\n";
   dash += sep;
   dash += "║ BIAIS DE MARCHÉ\n";
   dash += "║  M15 : " + BiasToString(g_bias.m15bias) + "\n";
   dash += "║  M5  : " + BiasToString(g_bias.m5bias) + "\n";
   dash += "║  M1  : " + BiasToString(g_bias.m1bias) + "\n";
   dash += "║  Global: " + BiasToString(g_bias.overall) + "\n";
   dash += sep;
   dash += "║ PD LEVELS\n";
   if(g_pd.calculated > 0)
     {
      dash += "║  PDH: " + DoubleToString(g_pd.pdh, g_digits) + "\n";
      dash += "║  PDL: " + DoubleToString(g_pd.pdl, g_digits) + "\n";
      dash += "║  PWH: " + DoubleToString(g_pd.pwh, g_digits) + "\n";
      dash += "║  PWL: " + DoubleToString(g_pd.pwl, g_digits) + "\n";
     }
   dash += sep;
   dash += "║ ORDER BLOCKS\n";
   dash += "║  Bull OB M5: " + (g_obBullM5.valid ? DoubleToString(g_obBullM5.low,g_digits)+"-"+DoubleToString(g_obBullM5.high,g_digits) : "N/A") + "\n";
   dash += "║  Bear OB M5: " + (g_obBearM5.valid ? DoubleToString(g_obBearM5.low,g_digits)+"-"+DoubleToString(g_obBearM5.high,g_digits) : "N/A") + "\n";
   dash += sep;
   dash += "║ FVG\n";
   dash += "║  Bull FVG M5: " + (g_fvgBullM5.valid ? DoubleToString(g_fvgBullM5.bottom,g_digits)+"-"+DoubleToString(g_fvgBullM5.top,g_digits) : "N/A") + "\n";
   dash += "║  Bear FVG M5: " + (g_fvgBearM5.valid ? DoubleToString(g_fvgBearM5.bottom,g_digits)+"-"+DoubleToString(g_fvgBearM5.top,g_digits) : "N/A") + "\n";
   dash += sep;
   dash += "║ MSS: " + (g_mssBull ? "BULL ✓" : (g_mssBear ? "BEAR ✓" : "aucun")) + "\n";
   dash += "║ Position: " + (HasOpenPosition() ? "OUVERTE" : "aucune") + "\n";
   dash += "╚═════════════════════════════╝";

   Comment(dash);
  }

//+------------------------------------------------------------------+
