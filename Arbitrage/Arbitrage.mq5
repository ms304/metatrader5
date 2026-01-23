//+------------------------------------------------------------------+
//|                                   MarketWatch_Arbi_Scanner_V4.mq5|
//|                                  Copyright 2024, Trading AI Corp |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "3.01"
#property strict

// Structure pour définir un triangle de devises
struct Triangle {
   string s1, s2, s3;      
   string c1;              // Devise de départ
   datetime lastAlert;     
};

Triangle Triangles[];      
int totalTriangles = 0;

// --- Paramètres d'entrée
input int    RefreshMs = 500;            // Rafraîchissement (ms)
input double MinProfitAlert = 0.0001;    // Seuil d'alerte (0.0001 = 0.01%)
input int    AlertCooldownSeconds = 60;  // Attendre X sec avant de relogger le même triangle

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   Print("--- Démarrage du Scanner d'Arbitrage V4 ---");
   FindTriangles();
   EventSetMillisecondTimer(RefreshMs);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   Comment("");
}

void OnTimer() {
   string output = "--- SCANNER D'ARBITRAGE RÉEL ---\n";
   output += "Triangles surveillés : " + (string)totalTriangles + "\n";
   output += "Seuil d'alerte : " + DoubleToString(MinProfitAlert * 100, 4) + "%\n";
   output += "----------------------------------------------------------\n";
   
   int foundCount = 0;
   datetime now = TimeCurrent();

   for(int i = 0; i < totalTriangles; i++) {
      double profit = CalculateRealProfit(Triangles[i]);
      
      // On affiche à l'écran si profit > 0 (mais réaliste < 5%)
      if(profit > 0 && profit < 0.05) { 
         output += StringFormat("TRI: %s-%s-%s | PROFIT: %.4f%%\n", 
                  Triangles[i].s1, Triangles[i].s2, Triangles[i].s3, profit * 100);
         foundCount++;

         // LOG DANS LA ZONE EXPERTS
         if(profit >= MinProfitAlert) {
            if(now - Triangles[i].lastAlert >= AlertCooldownSeconds) {
               Print(StringFormat("[ARBITRAGE] %s-%s-%s | Profit: %.4f%%", 
                     Triangles[i].s1, Triangles[i].s2, Triangles[i].s3, profit * 100));
               Triangles[i].lastAlert = now;
            }
         }
      }
   }

   if(foundCount == 0) output += "\nAucun profit détecté après spreads.";
   Comment(output);
}

//+------------------------------------------------------------------+
//| CALCUL DU PROFIT RÉEL                                           |
//+------------------------------------------------------------------+
double CalculateRealProfit(Triangle &t) {
   double amount = 1000.0;
   string currentCur = t.c1; 

   // Simuler les 3 étapes de conversion
   amount = ExecuteTrade(amount, currentCur, t.s1, currentCur);
   if(amount <= 0) return -1;
   
   amount = ExecuteTrade(amount, currentCur, t.s2, currentCur);
   if(amount <= 0) return -1;
   
   amount = ExecuteTrade(amount, currentCur, t.s3, currentCur);
   if(amount <= 0) return -1;

   return (amount / 1000.0) - 1.0;
}

// Fonction de simulation de transaction corrigée
double ExecuteTrade(double amount, string fromCur, string symbol, string &toCur) {
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick) || tick.ask <= 0) return 0;

   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string profit = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);

   if(fromCur == base) {
      toCur = profit;
      return amount * tick.bid; // Vente de la base
   } 
   else if(fromCur == profit) {
      toCur = base;
      return amount / tick.ask; // Achat de la base
   }
   return 0;
}

//+------------------------------------------------------------------+
//| RECHERCHE DES TRIANGLES                                         |
//+------------------------------------------------------------------+
void FindTriangles() {
   int total = SymbolsTotal(true);
   ArrayFree(Triangles);
   totalTriangles = 0;

   for(int i = 0; i < total; i++) {
      string s1 = SymbolName(i, true);
      string b1 = SymbolInfoString(s1, SYMBOL_CURRENCY_BASE);
      string q1 = SymbolInfoString(s1, SYMBOL_CURRENCY_PROFIT);

      for(int j = 0; j < total; j++) {
         string s2 = SymbolName(j, true);
         if(s1 == s2) continue;
         string b2 = SymbolInfoString(s2, SYMBOL_CURRENCY_BASE);
         string q2 = SymbolInfoString(s2, SYMBOL_CURRENCY_PROFIT);

         if(b1 == b2 || b1 == q2 || q1 == b2 || q1 == q2) {
            for(int k = 0; k < total; k++) {
               string s3 = SymbolName(k, true);
               if(s3 == s1 || s3 == s2) continue;
               
               if(IsValidTriangle(s1, s2, s3)) {
                  if(!AlreadyAdded(s1, s2, s3)) {
                     ArrayResize(Triangles, totalTriangles + 1);
                     Triangles[totalTriangles].s1 = s1;
                     Triangles[totalTriangles].s2 = s2;
                     Triangles[totalTriangles].s3 = s3;
                     Triangles[totalTriangles].c1 = b1; 
                     Triangles[totalTriangles].lastAlert = 0;
                     totalTriangles++;
                  }
               }
            }
         }
      }
   }
   Print("Scan terminé. ", totalTriangles, " triangles identifiés.");
}

bool IsValidTriangle(string s1, string s2, string s3) {
   string c[6];
   c[0] = SymbolInfoString(s1, SYMBOL_CURRENCY_BASE);
   c[1] = SymbolInfoString(s1, SYMBOL_CURRENCY_PROFIT);
   c[2] = SymbolInfoString(s2, SYMBOL_CURRENCY_BASE);
   c[3] = SymbolInfoString(s2, SYMBOL_CURRENCY_PROFIT);
   c[4] = SymbolInfoString(s3, SYMBOL_CURRENCY_BASE);
   c[5] = SymbolInfoString(s3, SYMBOL_CURRENCY_PROFIT);

   for(int i=0; i<6; i++) {
      int count = 0;
      for(int j=0; j<6; j++) if(c[i] == c[j]) count++;
      if(count != 2) return false;
   }
   return true;
}

bool AlreadyAdded(string s1, string s2, string s3) {
   for(int i=0; i<totalTriangles; i++) {
      int m = 0;
      if(Triangles[i].s1 == s1 || Triangles[i].s1 == s2 || Triangles[i].s1 == s3) m++;
      if(Triangles[i].s2 == s1 || Triangles[i].s2 == s2 || Triangles[i].s2 == s3) m++;
      if(Triangles[i].s3 == s1 || Triangles[i].s3 == s2 || Triangles[i].s3 == s3) m++;
      if(m == 3) return true;
   }
   return false;
}
