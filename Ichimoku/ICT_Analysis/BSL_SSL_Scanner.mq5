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

// Historique permanent des alertes déjà émises (jamais purgé)
string        g_alertedSymbols[];
datetime      g_alertedTimes[];
int           g_alertedCount = 0;

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
   ArrayResize(g_alertedSymbols, 0);
   ArrayResize(g_alertedTimes,   0);
   g_alertedCount = 0;
   g_lastScan = 0;

   // Lancer un premier scan immédiat
   ScanAllSymbols();

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Comment("");
   ArrayFree(g_signals);
   ArrayFree(g_alertedSymbols);
   ArrayFree(g_alertedTimes);
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
//|                                                                |
//|  RAPPEL CONVENTION : r[] est ArraySetAsSeries(true)            |
//|    → r[0]  = bougie la plus RÉCENTE                            |
//|    → r[N]  = bougie la plus ANCIENNE (passé)                   |
//|  Donc : index plus grand = plus ancien dans le temps           |
//|                                                                |
//|  SÉQUENCE RECHERCHÉE (ordre chronologique) :                   |
//|  1) Un swing high (BSL) existe à bar SH (dans le passé)        |
//|  2) Une bougie à bar B1 < SH sweepe ce BSL :                   |
//|       high[B1] > BSL  ET  close[B1] < BSL                      |
//|  3) APRÈS le sweep BSL (bar B1), le prix fait un move baissier |
//|  4) Un swing low (SSL) existait à bar SL > B1 (encore plus     |
//|     dans le passé, donc formé AVANT le sweep BSL)              |
//|  5) Une bougie à bar B2 < B1 sweepe ce SSL :                   |
//|       low[B2] < SSL  ET  close[B2] > SSL                       |
//|  6) B2 doit être récent (≤ SignalExpiryBars depuis bar 0)      |
//+------------------------------------------------------------------+
void AnalyzeSymbol(string sym)
  {
   int needed = SweepBarsBack + SwingLookback * 2 + 5;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(sym, ScanTimeframe, 0, needed, r);
   if(copied < needed * 0.7) return;

   int    available = copied;
   double symPoint  = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(symPoint == 0) return;
   double minSwing  = MinSwingPoints * symPoint;

   // ── Étape 1 : Détecter swing highs et swing lows ─────────────
   // Les deux tableaux sont remplis dans l'ordre croissant des index
   // (donc du plus récent au plus ancien)

   SwingHigh swingHighs[];
   SwingLow  swingLows[];
   int nhCount = 0, nlCount = 0;

   for(int i = SwingLookback; i < available - SwingLookback; i++)
     {
      // ── Swing High ──
      bool isHigh = true;
      for(int j = 1; j <= SwingLookback; j++)
        {
         if(r[i].high <= r[i-j].high || r[i].high <= r[i+j].high)
           { isHigh = false; break; }
        }
      if(isHigh)
        {
         // Filtrer les swings trop proches du précédent
         if(nhCount == 0 || MathAbs(r[i].high - swingHighs[nhCount-1].price) > minSwing)
           {
            ArrayResize(swingHighs, nhCount + 1);
            swingHighs[nhCount].price    = r[i].high;
            swingHighs[nhCount].barIndex = i;
            swingHighs[nhCount].time     = r[i].time;
            swingHighs[nhCount].swept    = false;
            swingHighs[nhCount].sweepBar = -1;
            nhCount++;
           }
        }

      // ── Swing Low ──
      bool isLow = true;
      for(int j = 1; j <= SwingLookback; j++)
        {
         if(r[i].low >= r[i-j].low || r[i].low >= r[i+j].low)
           { isLow = false; break; }
        }
      if(isLow)
        {
         if(nlCount == 0 || MathAbs(r[i].low - swingLows[nlCount-1].price) > minSwing)
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
     }

   if(nhCount < 1 || nlCount < 1) return;

   // ── Étape 2 : Pour chaque swing high, chercher son sweep BSL ──
   //
   // On cherche une bougie B1 (index B1 < swingHighs[hi].barIndex)
   // qui perce par le haut mais clôture sous le swing high.
   // "Plus petit index" = plus récent dans le temps.

   for(int hi = 0; hi < nhCount; hi++)
     {
      double bslPrice  = swingHighs[hi].price;
      int    bslBar    = swingHighs[hi].barIndex; // bar du swing high lui-même

      // Parcourir les bougies APRÈS le swing high (index décroissant = plus récent)
      for(int b1 = bslBar - 1; b1 >= 1; b1--)
        {
         if(r[b1].high > bslPrice)
           {
            if(r[b1].close < bslPrice)
              {
               // ✓ Sweep BSL confirmé à la bougie b1
               swingHighs[hi].swept    = true;
               swingHighs[hi].sweepBar = b1;
              }
            // Que ce soit un sweep ou une cassure franche, on s'arrête :
            // la première bougie qui touche le niveau est décisive
            break;
           }
        }
     }

   // ── Étape 3 : Pour chaque BSL sweepé, chercher le sweep SSL ──
   //
   // Conditions strictes :
   //  a) Le swing low (SSL candidat) doit être ANTÉRIEUR au sweep BSL
   //     → son barIndex > B1  (plus grand index = plus ancien)
   //  b) Le SSL doit aussi être ANTÉRIEUR au swing high lui-même
   //     → son barIndex > bslBar  n'est pas obligatoire mais
   //        il doit exister AVANT le sweep BSL, donc barIndex > b1
   //  c) Une bougie B2, avec b1 > B2 >= 1 (après le sweep BSL, donc
   //     plus récente que B1), doit sweeper ce SSL :
   //       low[B2] < sslPrice  ET  close[B2] > sslPrice
   //  d) Move baissier entre B1 et B2 : le prix doit effectivement
   //     descendre depuis le sweep BSL jusqu'au SSL
   //  e) B2 doit être récent (index ≤ SignalExpiryBars)

   for(int hi = 0; hi < nhCount; hi++)
     {
      if(!swingHighs[hi].swept) continue;

      int    b1       = swingHighs[hi].sweepBar; // bar du sweep BSL
      double bslPrice = swingHighs[hi].price;

      // Chercher le swing low candidat (SSL) :
      // Il doit avoir été formé AVANT le sweep BSL → barIndex > b1
      // On prend le SSL le plus récent qui satisfait cette condition
      int    sslBar   = -1;
      double sslPrice = 0;

      for(int li = 0; li < nlCount; li++)
        {
         if(swingLows[li].barIndex > b1) // plus ancien que le sweep BSL ✓
           {
            sslBar   = swingLows[li].barIndex;
            sslPrice = swingLows[li].price;
            break; // premier trouvé = le plus récent parmi les candidats
           }
        }

      if(sslBar < 0) continue; // aucun swing low antérieur au sweep BSL

      // Le SSL doit être sous le BSL (logique : on a sweepé un haut,
      // puis on redescend chercher un bas)
      if(sslPrice >= bslPrice) continue;

      // Chercher le sweep du SSL sur les bougies ENTRE b1 et bar 0
      // (bougies plus récentes que le sweep BSL, index < b1)
      // On cherche aussi uniquement dans la fenêtre MaxBarsAfterBSLSweep
      int searchLimit = MathMax(1, b1 - MaxBarsAfterBSLSweep);

      for(int b2 = b1 - 1; b2 >= searchLimit; b2--)
        {
         if(r[b2].low < sslPrice)
           {
            if(r[b2].close > sslPrice)
              {
               // ✓ Sweep SSL confirmé à la bougie b2

               // Vérifier fraîcheur du signal
               if(HighlightOnlyFresh && b2 > SignalExpiryBars) break;

               // Vérifier move baissier entre b1 et b2 :
               // le low entre b1 et b2 doit être descendu sous le SSL
               // (déjà garanti par r[b2].low < sslPrice)
               // Confirmation supplémentaire : le close de b1 doit être
               // supérieur au close de b2 (direction baissière du move)
               if(r[b1].close <= r[b2].close) break;

               // ── Signal valide ──

               // Déjà alerté ?
               bool alreadyAlerted = false;
               for(int s = 0; s < g_alertedCount; s++)
                 {
                  if(g_alertedSymbols[s] == sym &&
                     g_alertedTimes[s]   == r[b2].time)
                    { alreadyAlerted = true; break; }
                 }
               if(alreadyAlerted) break;

               // Créer le signal
               ArrayResize(g_signals, g_signalCount + 1);
               g_signals[g_signalCount].symbol         = sym;
               g_signals[g_signalCount].signalTime     = r[b2].time;
               g_signals[g_signalCount].bslLevel       = bslPrice;
               g_signals[g_signalCount].sslLevel       = sslPrice;
               g_signals[g_signalCount].entryZoneHigh  = r[b2].close;
               g_signals[g_signalCount].entryZoneLow   = sslPrice - (5 * symPoint);
               g_signals[g_signalCount].barsSinceSignal= b2;
               g_signals[g_signalCount].alerted        = false;
               g_signalCount++;

               // Enregistrer dans l'historique permanent
               ArrayResize(g_alertedSymbols, g_alertedCount + 1);
               ArrayResize(g_alertedTimes,   g_alertedCount + 1);
               g_alertedSymbols[g_alertedCount] = sym;
               g_alertedTimes[g_alertedCount]   = r[b2].time;
               g_alertedCount++;

               // Envoyer l'alerte
               SendSignalAlert(g_signals[g_signalCount - 1], symPoint);
              }
            // Que ce soit sweep ou cassure, on s'arrête sur ce SSL
            break;
           }
        }
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
