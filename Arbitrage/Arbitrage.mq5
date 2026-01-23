//+------------------------------------------------------------------+
//|                                   Arbitrage_V2_RoundTrip.mq5     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "2.00"
#property strict

struct Triangle {
   string s1, s2, s3;
   string c1, c2, c3; // Les 3 devises (ex: EUR, USD, GBP)
};

Triangle Triangles[];
int totalTriangles = 0;

int OnInit() {
   FindTriangles();
   EventSetMillisecondTimer(500);
   return(INIT_SUCCEEDED);
}

void OnTimer() {
   string output = "--- SCANNER D'ARBITRAGE RÉEL ---\n";
   int found = 0;

   for(int i = 0; i < totalTriangles; i++) {
      double profit = GetRealArbitrageProfit(Triangles[i]);
      
      // Un vrai profit d'arbitrage dépasse rarement 0.01% (0.0001)
      if(profit > 0.00001 && profit < 0.1) { 
         output += StringFormat("Tri: %s-%s-%s | Profit: %.4f%%\n", 
                  Triangles[i].s1, Triangles[i].s2, Triangles[i].s3, profit * 100);
         found++;
      }
   }
   if(found == 0) output += "Aucun profit réel détecté (après spreads).";
   Comment(output);
}

//+------------------------------------------------------------------+
//| SIMULATION RÉELLE DE CONVERSION (Bout en bout)                  |
//+------------------------------------------------------------------+
double GetRealArbitrageProfit(Triangle &t) {
   // On part avec 1.0 unité de la monnaie de base de s1
   // Exemple pour EURUSD-GBPUSD-EURGBP : on part avec 1 EUR
   string startCurrency = SymbolInfoString(t.s1, SYMBOL_CURRENCY_BASE);
   double balance = 1.0;

   // 1. Convertir la monnaie de base de s1 vers l'autre monnaie de s1
   balance = Convert(startCurrency, balance, t.s1);

   // 2. Convertir vers la monnaie suivante via s2
   string currentCurrency = (startCurrency == SymbolInfoString(t.s1, SYMBOL_CURRENCY_BASE)) ? 
                             SymbolInfoString(t.s1, SYMBOL_CURRENCY_PROFIT) : SymbolInfoString(t.s1, SYMBOL_CURRENCY_BASE);
   balance = Convert(currentCurrency, balance, t.s2);

   // 3. Revenir à la monnaie de départ via s3
   currentCurrency = GetOtherCurrency(currentCurrency, t.s2);
   balance = Convert(currentCurrency, balance, t.s3);

   return balance - 1.0;
}

// Fonction pour convertir une monnaie vers une autre sur un symbole donné
double Convert(string fromCur, double amount, string symbol) {
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick)) return 0;
   
   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string profit = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);

   if(fromCur == base) {
      // On vend la base pour obtenir la monnaie de profit (ex: EUR -> USD)
      return amount * tick.bid; 
   } else if(fromCur == profit) {
      // On achète la base avec la monnaie de profit (ex: USD -> EUR)
      return amount / tick.ask;
   }
   return 0;
}

string GetOtherCurrency(string fromCur, string symbol) {
   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string profit = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   return (fromCur == base) ? profit : base;
}

//+------------------------------------------------------------------+
//| Initialisation des triangles (simplifiée pour l'exemple)        |
//+------------------------------------------------------------------+
void FindTriangles() {
   // Ici, garde ta fonction de recherche actuelle, 
   // elle remplira le tableau Triangles[] avec les noms des symboles.
   // Veille à bien vérifier que les devises se suivent.
}
