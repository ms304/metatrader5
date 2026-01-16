//+------------------------------------------------------------------+
//|                                         MaxMargin_Limit.mq5       |
//|                                  Copyright 2024, TradingViewEA    |
//|                              Logic: MAX LOTS (MARGIN LIMIT ONLY)  |
//+------------------------------------------------------------------+
#property copyright "SMC Trader"
#property version   "1.00"
#property script_show_inputs

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   string symbol = Symbol();
   double price  = SymbolInfoDouble(symbol, SYMBOL_ASK);
   
   // 1. Récupérer l'argent réellement disponible pour ouvrir un trade
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   // 2. Demander au broker : "Combien de marge faut-il pour 1.00 Lot ?"
   double marginForOneLot = 0.0;
   
   // La fonction OrderCalcMargin est la seule façon précise de le savoir (tient compte du levier, devise, etc.)
   if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, 1.0, price, marginForOneLot) || marginForOneLot == 0)
   {
      Alert("Erreur : Impossible de récupérer les exigences de marge pour ", symbol);
      return;
   }
   
   // 3. Calcul mathématique pur
   double maxLots = freeMargin / marginForOneLot;
   
   // 4. Nettoyage du résultat
   // On arrondit vers le bas selon le "step" du broker (ex: 0.01) pour ne pas dépasser la marge
   double volStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   maxLots = MathFloor(maxLots / volStep) * volStep;
   
   // Vérification par rapport à la taille max absolue autorisée par le broker (souvent 50 ou 100 lots)
   double limitMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(maxLots > limitMax) maxLots = limitMax;

   // 5. Affichage
   string msg = "=== LIMITE MAXIMALE (" + symbol + ") ===\n\n";
   msg += "Marge Libre : " + DoubleToString(freeMargin, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n";
   msg += "Prix Actuel : " + DoubleToString(price, 2) + "\n";
   msg += "Levier utilisé : 1:" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LEVERAGE)) + "\n\n";
   msg += "🔥 MAX LOTS POSSIBLES : " + DoubleToString(maxLots, 2);
   
   Alert(msg);
}
