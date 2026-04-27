//+------------------------------------------------------------------+
//|                                         Risk1Percent_Lot.mq5     |
//|                                  Copyright 2024, TradingViewEA    |
//|                              Logic: 1% RISK PER TRADE            |
//+------------------------------------------------------------------+
#property copyright "SMC Trader"
#property version   "1.00"
#property script_show_inputs

//+------------------------------------------------------------------+
//| Inputs                                                          |
//+------------------------------------------------------------------+
input double RiskPercent = 1.0;        // Risque en % du capital
input double StopLossPoints = 50.0;    // Stop Loss en points (à adapter selon votre stratégie)

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   string symbol = Symbol();
   double price  = SymbolInfoDouble(symbol, SYMBOL_ASK);
   
   // 1. Récupérer le capital total du compte
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // 2. Calculer le montant à risquer (1% du capital)
   double riskAmount = accountEquity * (RiskPercent / 100.0);
   
   // 3. Déterminer la distance du Stop Loss en prix
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double stopLossDistance = StopLossPoints * point;
   
   // 4. Calculer la valeur du tick pour ce symbole
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // 5. Calculer combien de ticks représentent notre Stop Loss
   double ticksPerStopLoss = stopLossDistance / tickSize;
   
   // 6. Calculer la perte par lot pour ce Stop Loss
   double lossPerLot = ticksPerStopLoss * tickValue;
   
   // 7. Calculer le nombre de lots pour risquer exactement riskAmount
   double lots = riskAmount / lossPerLot;
   
   // 8. Nettoyage du résultat selon les règles du broker
   double volStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / volStep) * volStep;
   
   // 9. Vérification des limites broker
   double limitMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double limitMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   
   if(lots < limitMin) lots = limitMin;
   if(lots > limitMax) lots = limitMax;
   
   // 10. Vérification supplémentaire : marge disponible
   double marginRequired = 0.0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, symbol, lots, price, marginRequired))
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(marginRequired > freeMargin)
      {
         // Réduire les lots si marge insuffisante
         lots = (freeMargin / marginRequired) * lots;
         lots = MathFloor(lots / volStep) * volStep;
         if(lots < limitMin) lots = limitMin;
      }
   }
   
   // 11. Affichage détaillé
   string msg = "=== GESTION DU RISQUE 1% (" + symbol + ") ===\n\n";
   msg += "Capital (Equity) : " + DoubleToString(accountEquity, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n";
   msg += "Risque choisi : " + DoubleToString(RiskPercent, 1) + "%\n";
   msg += "Montant risqué : " + DoubleToString(riskAmount, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n";
   msg += "Stop Loss : " + DoubleToString(StopLossPoints, 0) + " points\n";
   msg += "Distance SL : " + DoubleToString(stopLossDistance, 5) + " pips\n\n";
   msg += "Valeur du tick : " + DoubleToString(tickValue, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n";
   msg += "Ticks par SL : " + DoubleToString(ticksPerStopLoss, 1) + "\n";
   msg += "Perte par lot : " + DoubleToString(lossPerLot, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n\n";
   msg += "💰 LOTS À UTILISER : " + DoubleToString(lots, 2) + " lots\n";
   msg += "Perte max attendue : " + DoubleToString(lossPerLot * lots, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY);
   
   Alert(msg);
   Print(msg);
   
   // 12. Option : placer un ordre avec ces calculs (optionnel)
   /*
   CTrade trade;
   double sl = price - stopLossDistance;
   double tp = price + (stopLossDistance * 2); // TP à 2x le SL par exemple
   trade.Buy(lots, symbol, price, sl, tp, "Achat avec risque 1%");
   */
}
