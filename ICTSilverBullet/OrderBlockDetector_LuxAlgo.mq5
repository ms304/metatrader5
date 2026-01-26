//+------------------------------------------------------------------+
//|                                    OrderBlockDetector_LuxAlgo.mq5|
//|                                  Copyright 2024, LuxAlgo MT5 Port|
//+------------------------------------------------------------------+
#property copyright "LuxAlgo / Transcription MT5"
#property version   "1.07"
#property strict

input group "=== Paramètres LuxAlgo ==="
input int      InpLength         = 5;          // Volume Pivot Length
input int      InpMaxBoxes       = 3;          // Nombre d'OB à afficher (comme LuxAlgo)
input int      InpHistory        = 1000;       // Bougies à scanner
input string   InpMitigation     = "Wick";     // Mitigation: Wick ou Close

input group "=== Apparence ==="
input color    InpBullColor      = C'22,148,0';   // Vert
input color    InpBearColor      = C'255,17,0';   // Rouge
input bool     InpShowMitigated  = false;         // METTRE A FALSE POUR NETTOYER
input int      InpOpacity        = 0;             // (Non utilisé, MT5 gère mal l'alpha)

struct OrderBlock {
   double   top;
   double   btm;
   datetime time;
   bool     active;
   string   type;
};

OrderBlock AllOBs[];
string Prefix = "LuxOB_";

int OnInit() {
   ObjectsDeleteAll(0, Prefix);
   FullScan();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { ObjectsDeleteAll(0, Prefix); }

void OnTick() {
   static datetime lastBar = 0;
   if(iTime(_Symbol, _Period, 0) != lastBar) {
      lastBar = iTime(_Symbol, _Period, 0);
      FullScan();
   }
}

void FullScan() {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, InpHistory, rates);
   if(copied < InpLength * 2 + 1) return;

   ArrayResize(AllOBs, 0);
   int last_os = -1;

   // 1. Scan de l'historique pour détecter les OB
   for(int i = copied - (InpLength * 2) - 1; i >= 0; i--) {
      
      int pIdx = i + InpLength; // Index du pivot potentiel
      
      // Détection Pivot de Volume
      bool isPivot = true;
      long v = rates[pIdx].tick_volume;
      for(int j = 1; j <= InpLength; j++) {
         if(rates[pIdx+j].tick_volume >= v || rates[pIdx-j].tick_volume > v) {
            isPivot = false; break;
         }
      }

      if(isPivot) {
         // Calcul Upper/Lower sur 'length' bougies AVANT le pivot (comme Pine Script)
         double upper = 0, lower = 999999;
         for(int k = 1; k <= InpLength; k++) {
            if(rates[pIdx+k].high > upper) upper = rates[pIdx+k].high;
            if(rates[pIdx+k].low < lower)  lower = rates[pIdx+k].low;
         }

         // Détermination du Biais OS
         int current_os = last_os;
         if(rates[pIdx].high > upper) current_os = 0;      // Bearish
         else if(rates[pIdx].low < lower) current_os = 1; // Bullish
         last_os = current_os;

         if(current_os != -1) {
            OrderBlock ob;
            ob.time = rates[pIdx].time;
            ob.active = true;
            ob.type = (current_os == 1) ? "BULL" : "BEAR";
            double hl2 = (rates[pIdx].high + rates[pIdx].low) / 2.0;

            if(ob.type == "BULL") { ob.top = hl2; ob.btm = rates[pIdx].low; }
            else { ob.top = rates[pIdx].high; ob.btm = hl2; }

            // Vérifier si l'OB a été traversé depuis sa création
            for(int m = pIdx - 1; m >= 0; m--) {
               if(InpMitigation == "Wick") {
                  if(ob.type == "BULL" && rates[m].low < ob.btm) { ob.active = false; break; }
                  if(ob.type == "BEAR" && rates[m].high > ob.top) { ob.active = false; break; }
               } else {
                  if(ob.type == "BULL" && rates[m].close < ob.btm) { ob.active = false; break; }
                  if(ob.type == "BEAR" && rates[m].close > ob.top) { ob.active = false; break; }
               }
            }

            // Filtrage : On n'ajoute que si c'est actif (ou si demandé)
            if(ob.active || InpShowMitigated) {
               int s = ArraySize(AllOBs);
               ArrayResize(AllOBs, s + 1);
               AllOBs[s] = ob;
            }
         }
      }
   }
   DrawOBs();
}

void DrawOBs() {
   ObjectsDeleteAll(0, Prefix);
   
   int bulls = 0, bears = 0;
   // On parcourt de la fin (plus récent) vers le début
   for(int i = ArraySize(AllOBs)-1; i >= 0; i--) {
      
      if(AllOBs[i].type == "BULL" && bulls < InpMaxBoxes) {
         CreateBox(Prefix+"B"+(string)i, AllOBs[i].time, AllOBs[i].top, AllOBs[i].btm, InpBullColor);
         bulls++;
      }
      if(AllOBs[i].type == "BEAR" && bears < InpMaxBoxes) {
         CreateBox(Prefix+"R"+(string)i, AllOBs[i].time, AllOBs[i].top, AllOBs[i].btm, InpBearColor);
         bears++;
      }
   }
}

void CreateBox(string name, datetime t1, double p1, double p2, color clr) {
   if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, TimeCurrent(), p2)) {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }
}
