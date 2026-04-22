//+------------------------------------------------------------------+
//|   BSL / SSL SWEEP SCANNER — MULTI-ACTIFS MARKETWATCH            |
//|   Pattern : Sweep BSL → Sweep SSL → Alerte LONG vers BSL        |
//|   Version 1.00                                                   |
//+------------------------------------------------------------------+
//
//  LOGIQUE DU PATTERN RECHERCHÉ
//  ─────────────────────────────────────────────────────────────────
//  1) Le prix monte et SWEEPE un swing high (Buy Side Liquidity = BSL)
//     → bougie qui dépasse le swing high mais CLÔTURE EN DESSOUS
//  2) Ensuite, le prix descend et SWEEPE un swing low (Sell Side
//     Liquidity = SSL) plus bas que le SSL précédent
//     → bougie qui dépasse le swing low mais CLÔTURE AU-DESSUS
//  3) Cette double séquence = signal LONG pour aller récupérer le BSL
//     initialement sweepé (cible = niveau du BSL sweepé)
//  ─────────────────────────────────────────────────────────────────
//  L'EA s'attache sur N'IMPORTE QUEL graphique (l'actif/TF de ce
//  graphique n'a aucune importance). Il scanne le MarketWatch entier
//  sur le timeframe choisi en paramètre.
//+------------------------------------------------------------------+

#property version   "1.00"
#property copyright "BSL SSL Scanner"
#property strict

//+------------------------------------------------------------------+
//|  PARAMÈTRES                                                     |
//+------------------------------------------------------------------+

input ENUM_TIMEFRAMES ScanTimeframe   = PERIOD_M15;  // Timeframe de scan
input int   SwingLookback             = 5;           // Bougies pivot pour swing H/L
input int   SweepBarsBack             = 50;          // Bougies analysées par actif
input int   MaxBarsAfterBSLSweep      = 30;          // Délai max entre BSL sweep et SSL sweep
input int   MinSwingPoints            = 10;          // Taille minimale d'un swing (points)
input int   ScanIntervalSeconds       = 60;          // Intervalle de scan (secondes)
input bool  AlertPopup                = true;        // Alerte popup MT5
input bool  AlertSound                = true;        // Alerte sonore
input bool  AlertEmail                = false;       // Alerte email
input bool  AlertPush                 = false;       // Notification push mobile
input bool  ShowDashboard             = true;        // Afficher tableau de bord
input bool  HighlightOnlyFresh        = true;        // Alerter seulement les nouveaux signaux
input int   SignalExpiryBars          = 3;           // Signal expire après N bougies

//+------------------------------------------------------------------+
//|  STRUCTURES                                                     |
//+------------------------------------------------------------------+

struct SwingHigh
  {
   double   price;
   int      barIndex;  // index dans le tableau (0 = bougie la plus récente)
   datetime time;
   bool     swept;     // a-t-il été sweepé ?
   int      sweepBar;  // bar index de la bougie qui l'a sweepé
  };

struct SwingLow
  {
   double   price;
   int      barIndex;
   datetime time;
   bool     swept;
   int      sweepBar;
  };

struct PatternSignal
  {
   string   symbol;
   datetime signalTime;
   double   bslLevel;       // Niveau du BSL sweepé (cible LONG)
   double   sslLevel;       // Niveau du SSL sweepé (zone d'entrée)
   double   entryZoneHigh;  // Zone d'entrée haute (au-dessus du SSL)
   double   entryZoneLow;   // Zone d'entrée basse
   int      barsSinceSignal;
   bool     alerted;        // Alerte déjà envoyée
  };

//+------------------------------------------------------------------+
//|  VARIABLES GLOBALES                                             |
//+------------------------------------------------------------------+

PatternSignal g_signals[];       // Signaux actifs
int           g_signalCount = 0;

datetime      g_lastScan = 0;
int           g_totalSymbols = 0;
int           g_scannedCount = 0;
string        g_lastScanTime = "";
string        g_statusMsg = "En attente...";

//+------------------------------------------------------------------+
//|  INIT                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("=== BSL/SSL SWEEP SCANNER démarré ===");
   Print("Timeframe: ", EnumToString(ScanTimeframe));
   Print("Lookback: ", SwingLookback, " | Bougies analysées: ", SweepBarsBack);

   ArrayResize(g_signals, 0);
   g_lastScan = 0;

   // Lancer un premier scan immédiat
   ScanAllSymbols();

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Comment("");
   ArrayFree(g_signals);
   Print("BSL/SSL Scanner arrêté.");
  }

//+------------------------------------------------------------------+
//|  TICK                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(TimeCurrent() - g_lastScan >= ScanIntervalSeconds)
     {
      g_lastScan = TimeCurrent();
      ScanAllSymbols();
     }

   if(ShowDashboard) DrawDashboard();
  }

//+------------------------------------------------------------------+
//|  SCAN DE TOUS LES SYMBOLES DU MARKETWATCH                      |
//+------------------------------------------------------------------+
void ScanAllSymbols()
  {
   g_totalSymbols = SymbolsTotal(true); // true = seulement MarketWatch
   g_scannedCount = 0;
   g_lastScanTime = TimeToString(TimeCurrent(), TIME_MINUTES | TIME_SECONDS);
   g_statusMsg    = "Scan en cours...";

   // Purger les anciens signaux expirés
   PurgeExpiredSignals();

   for(int i = 0; i < g_totalSymbols; i++)
     {
      string sym = SymbolName(i, true);
      if(sym == "") continue;

      // S'assurer que le symbole est disponible
      if(!SymbolSelect(sym, true)) continue;

      // Analyser ce symbole
      AnalyzeSymbol(sym);
      g_scannedCount++;
     }

   g_statusMsg = "Dernier scan: " + g_lastScanTime + " (" + IntegerToString(g_scannedCount) + " actifs)";
  }

//+------------------------------------------------------------------+
//|  ANALYSE D'UN SYMBOLE                                          |
//+------------------------------------------------------------------+
void AnalyzeSymbol(string sym)
  {
   int needed = SweepBarsBack + SwingLookback * 2 + 5;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(sym, ScanTimeframe, 0, needed, r);
   if(copied < needed * 0.7) return; // Données insuffisantes

   int available = copied;
   double symPoint = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(symPoint == 0) return;
   double minSwing = MinSwingPoints * symPoint;

   // ── Étape 1 : Détecter tous les swing highs et lows ──────────

   SwingHigh swingHighs[];
   SwingLow  swingLows[];
   int       nhCount = 0, nlCount = 0;

   for(int i = SwingLookback; i < available - SwingLookback; i++)
     {
      // Swing High
      bool isHigh = true;
      for(int j = 1; j <= SwingLookback; j++)
        {
         if(r[i].high <= r[i-j].high || r[i].high <= r[i+j].high)
           { isHigh = false; break; }
        }
      if(isHigh && (ArraySize(swingHighs) == 0 || MathAbs(r[i].high - swingHighs[nhCount-1].price) > minSwing))
        {
         ArrayResize(swingHighs, nhCount + 1);
         swingHighs[nhCount].price    = r[i].high;
         swingHighs[nhCount].barIndex = i;
         swingHighs[nhCount].time     = r[i].time;
         swingHighs[nhCount].swept    = false;
         swingHighs[nhCount].sweepBar = -1;
         nhCount++;
        }

      // Swing Low
      bool isLow = true;
      for(int j = 1; j <= SwingLookback; j++)
        {
         if(r[i].low >= r[i-j].low || r[i].low >= r[i+j].low)
           { isLow = false; break; }
        }
      if(isLow && (ArraySize(swingLows) == 0 || MathAbs(r[i].low - swingLows[nlCount-1].price) > minSwing))
        {
         ArrayResize(swingLows, nlCount + 1);
         swingLows[nlCount].price    = r[i].low;
         swingLows[nlCount].barIndex = i;
         swingLows[nlCount].time     = r[i].time;
         swingLows[nlCount].swept    = false;
         swingLows[nlCount].sweepBar = -1;
         nlCount++;
        }
     }

   if(nhCount < 2 || nlCount < 2) return;

   // ── Étape 2 : Détecter les sweeps de BSL ─────────────────────
   // Un sweep BSL = une bougie dépasse un swing high MAIS clôture SOUS ce niveau

   for(int hi = 0; hi < nhCount; hi++)
     {
      double bslPrice = swingHighs[hi].price;
      int    bslBar   = swingHighs[hi].barIndex;

      // Chercher une bougie APRÈS ce swing high qui le sweep
      for(int k = bslBar - 1; k >= 1; k--)
        {
         // La bougie dépasse le swing high (wick au-dessus)
         if(r[k].high > bslPrice)
           {
            // Mais clôture EN DESSOUS = sweep confirmé (rejection)
            if(r[k].close < bslPrice)
              {
               swingHighs[hi].swept    = true;
               swingHighs[hi].sweepBar = k;
               break;
              }
            // Si elle clôture au-dessus, le niveau est cassé (pas un sweep)
            else
              { break; }
           }
        }
     }

   // ── Étape 3 : Pour chaque BSL sweepé, chercher un SSL sweep ──
   // Logique : après le sweep BSL, le prix doit ensuite sweeper un SSL
   // (descendre sous un swing low et clôturer au-dessus)

   for(int hi = 0; hi < nhCount; hi++)
     {
      if(!swingHighs[hi].swept) continue;

      int bslSweepBar = swingHighs[hi].sweepBar;
      double bslPrice = swingHighs[hi].price;

      // Chercher un swing low PLUS BAS formé AVANT le sweep BSL
      // (la cible SSL doit être un swing low précédent significatif)
      double targetSSL = -1;
      int    targetSSLBar = -1;

      for(int li = 0; li < nlCount; li++)
        {
         // Le swing low doit être antérieur au sweep BSL
         if(swingLows[li].barIndex <= bslSweepBar) continue;

         // Le swing low doit être sous le prix actuel (candidat SSL)
         targetSSL    = swingLows[li].price;
         targetSSLBar = swingLows[li].barIndex;
         break; // Premier SSL valide trouvé (le plus récent)
        }

      if(targetSSL < 0) continue;

      // Maintenant chercher le sweep de ce SSL APRÈS le sweep BSL
      bool sslSwept = false;
      int  sslSweepBar = -1;
      double sslSweepClose = 0;

      for(int k = bslSweepBar - 1; k >= 1; k--)
        {
         // Trop loin dans le temps = abandon
         if(bslSweepBar - k > MaxBarsAfterBSLSweep) break;

         // La bougie dépasse le SSL (wick en dessous)
         if(r[k].low < targetSSL)
           {
            // Mais clôture AU-DESSUS = sweep SSL confirmé (rejet)
            if(r[k].close > targetSSL)
              {
               sslSwept      = true;
               sslSweepBar   = k;
               sslSweepClose = r[k].close;
               break;
              }
            // Si elle clôture dessous = cassure, pas un sweep
            else
              { break; }
           }
        }

      if(!sslSwept) continue;

      // ── Étape 4 : SIGNAL TROUVÉ ! ─────────────────────────────
      // Le SSL sweep est le plus récent possible (sslSweepBar proche de 0)
      // On veut seulement les signaux frais (sslSweepBar petit)
      if(HighlightOnlyFresh && sslSweepBar > SignalExpiryBars) continue;

      // Vérifier si ce signal existe déjà
      bool alreadyExists = false;
      for(int s = 0; s < g_signalCount; s++)
        {
         if(g_signals[s].symbol == sym &&
            MathAbs((double)(g_signals[s].signalTime - r[sslSweepBar].time)) < 1)
           { alreadyExists = true; break; }
        }
      if(alreadyExists) continue;

      // Créer le signal
      double entryLow  = targetSSL - (5 * symPoint); // sous le SSL pour le SL
      double entryHigh = sslSweepClose;               // clôture du sweep = zone d'entrée

      ArrayResize(g_signals, g_signalCount + 1);
      g_signals[g_signalCount].symbol         = sym;
      g_signals[g_signalCount].signalTime     = r[sslSweepBar].time;
      g_signals[g_signalCount].bslLevel       = bslPrice;
      g_signals[g_signalCount].sslLevel       = targetSSL;
      g_signals[g_signalCount].entryZoneHigh  = entryHigh;
      g_signals[g_signalCount].entryZoneLow   = entryLow;
      g_signals[g_signalCount].barsSinceSignal= sslSweepBar;
      g_signals[g_signalCount].alerted        = false;
      g_signalCount++;

      // Envoyer l'alerte
      SendSignalAlert(g_signals[g_signalCount - 1], symPoint);
     }
  }

//+------------------------------------------------------------------+
//|  ENVOI DES ALERTES                                              |
//+------------------------------------------------------------------+
void SendSignalAlert(PatternSignal &sig, double symPoint)
  {
   if(sig.alerted) return;

   int    digits   = (int)SymbolInfoInteger(sig.symbol, SYMBOL_DIGITS);
   string tfStr    = TFToString(ScanTimeframe);

   string msg =
      "🎯 BSL/SSL SWEEP SIGNAL — " + sig.symbol + " [" + tfStr + "]\n" +
      "──────────────────────────────\n" +
      "📈 ENTRÉE LONG\n" +
      "  Zone entrée : " + DoubleToString(sig.entryZoneLow, digits) +
                  " – " + DoubleToString(sig.entryZoneHigh, digits) + "\n" +
      "  SSL sweepé  : " + DoubleToString(sig.sslLevel, digits) + "  (SL sous ce niveau)\n" +
      "  🎯 Cible TP  : " + DoubleToString(sig.bslLevel, digits) + "  (BSL initial)\n" +
      "──────────────────────────────\n" +
      "Heure signal : " + TimeToString(sig.signalTime, TIME_DATE | TIME_MINUTES);

   Print("═══ SIGNAL BSL/SSL ═══");
   Print(msg);

   if(AlertPopup)  Alert(msg);
   if(AlertSound)  PlaySound("alert.wav");
   if(AlertEmail)  SendMail("BSL/SSL Signal — " + sig.symbol, msg);
   if(AlertPush)   SendNotification("🎯 " + sig.symbol + " " + tfStr + " BSL/SSL LONG | TP: " + DoubleToString(sig.bslLevel, digits));

   sig.alerted = true;
  }

//+------------------------------------------------------------------+
//|  SUPPRESSION DES SIGNAUX EXPIRÉS                               |
//+------------------------------------------------------------------+
void PurgeExpiredSignals()
  {
   if(g_signalCount == 0) return;

   PatternSignal temp[];
   int newCount = 0;
   ArrayResize(temp, g_signalCount);

   for(int i = 0; i < g_signalCount; i++)
     {
      // Calculer combien de bougies se sont écoulées depuis le signal
      datetime lastBarArr[1];
      if(CopyTime(g_signals[i].symbol, ScanTimeframe, 0, 1, lastBarArr) > 0)
        {
         long tfSecs    = PeriodSeconds(ScanTimeframe);
         long elapsed   = (long)(TimeCurrent() - g_signals[i].signalTime);
         long barsElapsed = elapsed / tfSecs;

         if(barsElapsed <= SignalExpiryBars)
           {
            temp[newCount] = g_signals[i];
            newCount++;
           }
        }
     }

   ArrayResize(g_signals, newCount);
   g_signalCount = newCount;
  }

//+------------------------------------------------------------------+
//|  TABLEAU DE BORD                                               |
//+------------------------------------------------------------------+
void DrawDashboard()
  {
   string d = "";
   string sep = "─────────────────────────────────────\n";

   d += "╔══════ BSL/SSL SWEEP SCANNER ═══════╗\n";
   d += "║ TF: " + TFToString(ScanTimeframe);
   d += " | Pivot: " + IntegerToString(SwingLookback) + " bougies\n";
   d += "║ " + g_statusMsg + "\n";
   d += sep;

   if(g_signalCount == 0)
     {
      d += "║  Aucun signal actif\n";
     }
   else
     {
      d += "║  SIGNAUX ACTIFS (" + IntegerToString(g_signalCount) + ")\n";
      d += sep;

      for(int i = 0; i < g_signalCount; i++)
        {
         int digs = (int)SymbolInfoInteger(g_signals[i].symbol, SYMBOL_DIGITS);
         d += "║ 🎯 " + g_signals[i].symbol + "\n";
         d += "║    Entrée : ~" + DoubleToString(g_signals[i].entryZoneHigh, digs) + "\n";
         d += "║    SSL SL : " + DoubleToString(g_signals[i].sslLevel, digs) + "\n";
         d += "║    BSL TP : " + DoubleToString(g_signals[i].bslLevel, digs) + "\n";
         d += "║    Heure  : " + TimeToString(g_signals[i].signalTime, TIME_MINUTES) + "\n";
         if(i < g_signalCount - 1) d += sep;
        }
     }

   d += "╚═════════════════════════════════════╝";
   Comment(d);
  }

//+------------------------------------------------------------------+
//|  UTILITAIRES                                                   |
//+------------------------------------------------------------------+

string TFToString(ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "??";
     }
  }

//+------------------------------------------------------------------+
