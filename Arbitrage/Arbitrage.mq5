//+------------------------------------------------------------------+
//|                                   MarketWatch_Arbi_Scanner.mq5   |
//|                                  Copyright 2024, Trading AI Corp |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "2.00"
#property strict

// Structure pour définir un triangle de devises
struct Triangle {
   string s1, s2, s3;      // Noms des symboles (ex: EURUSD)
   string c1, c2, c3;      // Noms des devises (ex: EUR, USD, GBP)
};

Triangle Triangles[];      // Tableau des triangles détectés
int totalTriangles = 0;

// Paramètres
input int RefreshMs = 500;       // Vitesse de rafraîchissement (ms)
input double MinProfit = 0.0001; // Seuil d'affichage (0.01%)

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   Print("Recherche de triangles dans le MarketWatch...");
   FindTriangles();
   EventSetMillisecondTimer(RefreshMs);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   Comment("");
}

void OnTimer() {
   string output = "--- SCANNER D'ARBITRAGE RÉEL (Triangulaire) ---\n";
   output += "Triangles surveillés : " + (string)totalTriangles + "\n";
   output += "Méthode : Simulation Round-Trip (Bid/Ask inclus)\n";
   output += "----------------------------------------------------------\n";
   
   int found = 0;

   for(int i = 0; i < totalTriangles; i++) {
      double profit = CalculateRealProfit(Triangles[i]);
      
      // On affiche si le profit est "réaliste" (entre 0% et 2%)
      // Si c'est au dessus de 5%, c'est souvent une erreur de cotation du broker
      if(profit > 0 && profit < 0.05) { 
         output += StringFormat("TRI: %s -> %s -> %s | PROFIT: %.4f%%\n", 
                  Triangles[i].s1, Triangles[i].s2, Triangles[i].s3, profit * 100);
         found++;
      }
   }

   if(found == 0) output += "\nAucun profit détecté après spreads.\n(C'est normal, le marché est efficient)";
   
   Comment(output);
}

//+------------------------------------------------------------------+
//| CALCUL DU PROFIT RÉEL (SIMULATION DE TRANSACTION)               |
//+------------------------------------------------------------------+
double CalculateRealProfit(Triangle &t) {
   // On part avec 1000 unités de la devise de base du premier symbole
   double amount = 1000.0;
   string currentCur = t.c1; 

   // Étape 1 : Passer par le Symbole 1
   amount = ExecuteTrade(amount, currentCur, t.s1, currentCur);
   
   // Étape 2 : Passer par le Symbole 2
   amount = ExecuteTrade(amount, currentCur, t.s2, currentCur);
   
   // Étape 3 : Revenir à la devise de départ par le Symbole 3
   amount = ExecuteTrade(amount, currentCur, t.s3, currentCur);

   // Retourne le gain ou la perte en pourcentage
   return (amount / 1000.0) - 1.0;
}

// Fonction qui simule la conversion d'une monnaie à une autre sur un symbole
double ExecuteTrade(double amount, string fromCur, string symbol, string &toCur) {
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick) || tick.ask <= 0) return 0;

   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string profit = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);

   if(fromCur == base) {
      // On vend la base pour obtenir la devise de profit (ex: EUR -> USD)
      toCur = profit;
      return amount * tick.bid;
   } 
   else if(fromCur == profit) {
      // On achète la base avec la devise de profit (ex: USD -> EUR)
      toCur = base;
      return amount / tick.ask;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| RECHERCHE AUTOMATIQUE DES TRIANGLES                             |
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

         // Si s1 et s2 partagent une devise
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
                     Triangles[totalTriangles].c1 = b1; // On stocke la devise de départ
                     totalTriangles++;
                  }
               }
            }
         }
      }
   }
   Print("Scan terminé. Triangles trouvés : ", totalTriangles);
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
      if(count != 2) return false; // Chaque devise doit apparaître exactement 2 fois
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
