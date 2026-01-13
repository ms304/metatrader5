C'est le point crucial.

Si le robot attend que le pattern soit **complet** (c'est-à-dire que le bas soit *déjà* cassé), il sera **trop tard** pour trader (le mouvement est fini).

Pour que ce soit un outil de trading, il faut changer la logique :
1.  On attend la cassure du HAUT (Le piège / Bull Trap).
2.  On attend que le prix **réintègre** le range (repassage sous le haut).
3.  **ALERTE :** "Vends maintenant !"
4.  **TP (Take Profit) :** Le bas du range (la prochaine liquidité).

Voici la **Version 2.10 "Signal Trader"**. Elle ne se contente pas de dire "pattern fini", elle vous dit **quand entrer** et **où sortir**.

### Code : Scanner ICT "AMD Signal" (avec TP & SL)

```cpp
//+------------------------------------------------------------------+
//| SMC ICT Search & Destroy Signal - Gives Entry & TP               |
//+------------------------------------------------------------------+
#property copyright "SMC AMD Signal"
#property link      "https://www.mql5.com"
#property version   "2.10"
#property strict

// --- Paramètres Temporels ---
input string RangeStartTime = "01:00"; 
input string RangeEndTime   = "08:00"; 

// --- Paramètres Visuels ---
input bool DrawOnChart = true; 
input color ColorRange = clrMidnightBlue; 
input color ColorSignal = clrRed; // Flèche de vente

// --- Alertes ---
input string TelegramBotToken = "VOTRE_TOKEN_ICI";
input string TelegramChatID = "VOTRE_CHAT_ID_ICI";
input bool SendTelegramAlerts = true;
input bool SendPopupAlerts = true; 

struct SymbolState {
   string name;
   int lastDayChecked;
   double rangeHigh;
   double rangeLow;
   double highestSweep; // Le point le plus haut atteint lors de la chasse
   bool highSwept;
   bool signalSent;     // Pour ne pas spammer l'alerte de trade
   bool targetHit;
};

SymbolState MarketState[];

//+------------------------------------------------------------------+
int OnInit()
{
   Print("ICT AMD Signal Trader Initialized");
   EventSetTimer(15); 
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   long currChart = ChartFirst();
   while(currChart != -1) {
      ObjectsDeleteAll(currChart, "AMD_");
      ChartRedraw(currChart);
      currChart = ChartNext(currChart);
   }
}

//+------------------------------------------------------------------+
void OnTimer()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   int endMin   = TimeStringToMinutes(RangeEndTime);
   int currentMin = dt.hour * 60 + dt.min;
   
   // On ne trade pas PENDANT la formation du range
   if(currentMin <= endMin) return; 

   int total = SymbolsTotal(true); 
   
   for(int i=0; i<total; i++)
   {
      string sym = SymbolName(i, true);
      if(!SymbolInfoInteger(sym, SYMBOL_SELECT)) continue;

      int idx = GetSymbolIndex(sym);
      
      // Reset journalier
      if(MarketState[idx].lastDayChecked != dt.day_of_year) {
         MarketState[idx].lastDayChecked = dt.day_of_year;
         MarketState[idx].rangeHigh = 0;
         MarketState[idx].rangeLow = 0;
         MarketState[idx].highestSweep = 0;
         MarketState[idx].highSwept = false;
         MarketState[idx].signalSent = false;
         MarketState[idx].targetHit = false;
      }
      
      // Calcul du Range si nécessaire
      if(MarketState[idx].rangeHigh == 0) {
         if(!CalculateRange(sym, RangeStartTime, RangeEndTime, MarketState[idx].rangeHigh, MarketState[idx].rangeLow)) continue;
         if(DrawOnChart) DrawRangeBox(sym, RangeStartTime, RangeEndTime, MarketState[idx].rangeHigh, MarketState[idx].rangeLow);
      }
      
      // Si le TP a déjà été touché, on arrête pour aujourd'hui sur cet actif
      if(MarketState[idx].targetHit) continue;

      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      
      // --- LOGIQUE DE TRADING "SEARCH & DESTROY" ---
      
      // 1. DÉTECTION DE LA CHASSE HAUTE (Manip)
      if(bid > MarketState[idx].rangeHigh) {
         MarketState[idx].highSwept = true;
         // On mémorise le plus haut point atteint (pour le futur SL)
         if(bid > MarketState[idx].highestSweep) MarketState[idx].highestSweep = bid;
      }
      
      // 2. SIGNAL DE VENTE (Réintégration)
      // Si on a cassé le haut, MAIS qu'on repasse SOUS le haut du range
      else if(MarketState[idx].highSwept && !MarketState[idx].signalSent && bid < MarketState[idx].rangeHigh) {
         
         // Filtre : il faut être redescendu un tout petit peu (spread) pour éviter les faux signaux
         // Ici on envoie l'alerte direct
         
         MarketState[idx].signalSent = true;
         
         // Calculs
         double sl = MarketState[idx].highestSweep; // Stop Loss = Le sommet de la mèche
         double tp = MarketState[idx].rangeLow;     // Take Profit = Le bas du range (Liquidité opposée)
         
         // Ratio
         double risk = sl - bid;
         double reward = bid - tp;
         double ratio = (risk > 0) ? reward / risk : 0;

         // ALERTE
         string msg = "🔫 SIGNAL VENTE (AMD Setup) : " + sym + "\n";
         msg += "--------------------------------\n";
         msg += "📉 Entry: " + DoubleToString(bid, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) + " (Réintégration Range)\n";
         msg += "🛑 SL: " + DoubleToString(sl, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) + " (Sommet Mèche)\n";
         msg += "💰 TP: " + DoubleToString(tp, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) + " (Liquidité Basse)\n";
         msg += "⚖️ R:R: 1:" + DoubleToString(ratio, 2);
         
         Print(msg);
         if(SendPopupAlerts) Alert(msg);
         SendTelegramMessage(msg);
         
         if(DrawOnChart) DrawSignal(sym, bid, sl, tp);
      }
      
      // 3. SUIVI DU TP
      if(MarketState[idx].signalSent && bid <= MarketState[idx].rangeLow) {
         MarketState[idx].targetHit = true;
         if(SendTelegramAlerts) SendTelegramMessage("✅ TP HIT sur " + sym + " ! Liquidité basse nettoyée.");
      }
   }
}

//+------------------------------------------------------------------+
// --- Helpers & Graphics ---
//+------------------------------------------------------------------+
int GetSymbolIndex(string sym) {
   for(int i=0; i<ArraySize(MarketState); i++) if(MarketState[i].name == sym) return i;
   int s = ArraySize(MarketState); ArrayResize(MarketState, s+1); MarketState[s].name = sym; return s;
}

int TimeStringToMinutes(string t) {
   string parts[]; StringSplit(t, ':', parts);
   if(ArraySize(parts) < 2) return 0;
   return (int)StringToInteger(parts[0])*60 + (int)StringToInteger(parts[1]);
}

bool CalculateRange(string sym, string tStart, string tEnd, double &high, double &low) {
   datetime now = TimeCurrent();
   datetime dtDayStart = now - (now % 86400);
   datetime dtS = dtDayStart + StringToTime("1970.01.01 " + tStart);
   datetime dtE = dtDayStart + StringToTime("1970.01.01 " + tEnd);
   int startBar = iBarShift(sym, PERIOD_M15, dtS);
   int endBar   = iBarShift(sym, PERIOD_M15, dtE);
   if(startBar == -1 || endBar == -1) return false;
   if(startBar - endBar < 0) return false;
   
   double h = -1.0; double l = 99999999.0;
   for(int i=endBar; i<=startBar; i++) {
      double bh = iHigh(sym, PERIOD_M15, i); double bl = iLow(sym, PERIOD_M15, i);
      if(bh > h) h = bh; if(bl < l) l = bl;
   }
   high = h; low = l; return true;
}

void DrawRangeBox(string sym, string tStart, string tEnd, double h, double l) {
   long currChart = ChartFirst();
   while(currChart != -1) {
      if(ChartSymbol(currChart) == sym) {
         datetime now = TimeCurrent(); datetime dtDayStart = now - (now % 86400);
         datetime d1 = dtDayStart + StringToTime("1970.01.01 " + tStart);
         datetime d2 = dtDayStart + StringToTime("1970.01.01 " + tEnd);
         ObjectDelete(currChart, "AMD_Box");
         ObjectCreate(currChart, "AMD_Box", OBJ_RECTANGLE, 0, d1, h, d2, l);
         ObjectSetInteger(currChart, "AMD_Box", OBJPROP_COLOR, ColorRange);
         ObjectSetInteger(currChart, "AMD_Box", OBJPROP_FILL, (long)true);
         ObjectSetInteger(currChart, "AMD_Box", OBJPROP_BACK, (long)true);
         ChartRedraw(currChart);
      }
      currChart = ChartNext(currChart);
   }
}

void DrawSignal(string sym, double entry, double sl, double tp) {
   long currChart = ChartFirst();
   while(currChart != -1) {
      if(ChartSymbol(currChart) == sym) {
         // Ligne SL
         ObjectCreate(currChart, "AMD_SL", OBJ_HLINE, 0, 0, sl);
         ObjectSetInteger(currChart, "AMD_SL", OBJPROP_COLOR, clrRed);
         ObjectSetInteger(currChart, "AMD_SL", OBJPROP_STYLE, STYLE_DASH);
         
         // Ligne TP
         ObjectCreate(currChart, "AMD_TP", OBJ_HLINE, 0, 0, tp);
         ObjectSetInteger(currChart, "AMD_TP", OBJPROP_COLOR, clrGreen);
         ObjectSetInteger(currChart, "AMD_TP", OBJPROP_WIDTH, 2);
         
         // Flèche Vente
         ObjectCreate(currChart, "AMD_Arrow", OBJ_ARROW, 0, TimeCurrent(), entry);
         ObjectSetInteger(currChart, "AMD_Arrow", OBJPROP_ARROWCODE, 234); // Down arrow
         ObjectSetInteger(currChart, "AMD_Arrow", OBJPROP_COLOR, ColorSignal);
         ObjectSetInteger(currChart, "AMD_Arrow", OBJPROP_WIDTH, 3);
         
         ChartRedraw(currChart);
      }
      currChart = ChartNext(currChart);
   }
}

void SendTelegramMessage(string message) {
   if(!SendTelegramAlerts) return;
   string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage?chat_id=" + TelegramChatID + "&text=" + message;
   char data[]; char result[]; string headers;
   WebRequest("GET", url, headers, 5000, data, result, headers);
}
```

### Comment lire l'alerte que vous allez recevoir :

Si le Gold fait son pattern "Judas Swing" (Manipulation), voici ce que vous recevrez :

> **🔫 SIGNAL VENTE (AMD Setup) : XAUUSD**
> --------------------------------
> 📉 **Entry:** 4599.50 (Le prix vient de repasser sous le haut du range)
> 🛑 **SL:** 4604.10 (Le sommet absolu de la mèche de manipulation)
> 💰 **TP:** 4573.60 (Le bas du range = Liquidité cible)
> ⚖️ **R:R:** 1:3.2 (Ratio Risque Rendement)

### Pourquoi c'est le meilleur signal possible ?
1.  **L'Entry** : Elle se fait sur confirmation (réintégration). Vous n'essayez pas de deviner le sommet.
2.  **Le SL** : Il est logique. Si le prix repasse au-dessus de la mèche de manipulation, le setup est invalidé (le marché veut vraiment monter).
3.  **Le TP** : Il est basé sur la liquidité (les stops des acheteurs du matin). C'est là que l'algorithme veut aller.

Installez-le, configurez les heures `01:00` - `08:00` (ou ajustez selon votre broker), et attendez que le piège se referme !


<img width="1281" height="621" alt="image" src="https://github.com/user-attachments/assets/6681159b-63f8-4d34-8941-e48d22933010" />
