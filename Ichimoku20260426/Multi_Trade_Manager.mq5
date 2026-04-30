//+------------------------------------------------------------------+
//|                                        Multi_Trade_Manager.mq5  |
//|                                     Gestion multi-actifs CSV    |
//|                                          Version 2.00           |
//|                                      + Calcul lots automatique  |
//+------------------------------------------------------------------+
#property copyright "Multi Trade EA"
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| Paramètres d'entrée                                              |
//+------------------------------------------------------------------+
input string   FichierConfig = "Trades_Config.csv";  // Nom du fichier de configuration
input int      Slippage = 50;                       // Slippage maximum en points
input bool     ActiverLogsDetails = true;           // Activer les logs détaillés
input int      MagicNumberBase = 202500;            // Base pour les magic numbers

// === PARAMÈTRES POUR LE CALCUL AUTO DES LOTS ===
input bool     CalculAutoLots = false;              // Calcul auto du nombre de lots
input double   RisquePourcent = 1.0;                // Risque en % du compte (ex: 1.0 = 1%)
input double   StopLossPoints = 500;                // Stop Loss en points (pour calcul risque)
input double   LotsMax = 5.0;                       // Lots maximum autorisé
input double   LotsMin = 0.01;                      // Lots minimum autorisé
input bool     UtiliserMargePourMax = false;        // Utiliser la marge dispo comme limite
input double   PourcentageMargeMax = 50.0;          // % max de la marge à utiliser

//+------------------------------------------------------------------+
//| Structure pour un trade                                          |
//+------------------------------------------------------------------+
struct STradeConfig
{
   string   Symbole;        // Renommé de "Actif" à "Symbole" pour éviter conflit
   string   Type;           // "LONG" ou "SHORT"
   double   Entree;         // Prix de déclenchement (clôture bougie)
   double   TP;             // Take Profit
   double   SL;             // Stop Loss
   double   Lots;           // Volume en lots (peut être modifié par auto calc)
   double   LotsOriginal;   // Lots d'origine du CSV
   bool     IsActive;       // Renommé de "Actif" à "IsActive"
   int      MagicNumber;    // Identifiant unique
   bool     TradeExecute;   // Si le trade a déjà été exécuté
   datetime DerniereBougie; // Dernière bougie vérifiée
};

//+------------------------------------------------------------------+
//| Variables globales                                               |
//+------------------------------------------------------------------+
STradeConfig Trades[];
int TotalTrades = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("═══════════════════════════════════════════════════════");
   Print("⭐ MULTI TRADE MANAGER V2 - INITIALISATION ⭐");
   Print("═══════════════════════════════════════════════════════");
   
   if(CalculAutoLots)
   {
      Print("📊 MODE CALCUL AUTO LOTS ACTIF");
      Print("   Risque: ", RisquePourcent, "% du compte");
      Print("   Stop en points: ", StopLossPoints);
      Print("   Lots min: ", LotsMin, " | Lots max: ", LotsMax);
      if(UtiliserMargePourMax)
         Print("   Limite marge: ", PourcentageMargeMax, "% de la marge");
   }
   else
   {
      Print("📊 MODE LOTS FIXES (depuis CSV)");
   }
   
   if(!ChargerConfiguration())
   {
      Print("❌ Erreur: Impossible de charger le fichier de configuration");
      return(INIT_FAILED);
   }
   
   Print("✅ Configuration chargée - ", TotalTrades, " trade(s) paramétré(s)");
   Print("═══════════════════════════════════════════════════════");
   
   for(int i = 0; i < ArraySize(Trades); i++)
   {
      if(Trades[i].IsActive)
      {
         string lotsInfo = (CalculAutoLots) ? " (calcul auto)" : "";
         Print("[", i+1, "] ", Trades[i].Symbole, " - ", Trades[i].Type, 
               " | Entrée: ", Trades[i].Entree, " | TP: ", Trades[i].TP, 
               " | SL: ", Trades[i].SL, " | Lots: ", Trades[i].Lots, lotsInfo);
      }
   }
   Print("═══════════════════════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Charger la configuration depuis le fichier CSV                   |
//+------------------------------------------------------------------+
bool ChargerConfiguration()
{
   string chemin = "Files\\" + FichierConfig;
   int handle = FileOpen(chemin, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   
   if(handle == INVALID_HANDLE)
   {
      Print("❌ Fichier introuvable: ", chemin);
      Print("📁 Placez le fichier dans: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\");
      return false;
   }
   
   // Lire l'en-tête (première ligne)
   string entete = FileReadString(handle);
   
   // Lire les lignes de données
   while(!FileIsEnding(handle))
   {
      string ligne = FileReadString(handle);
      
      // Nettoyer la ligne (enlever les retours chariot)
      StringReplace(ligne, "\r", "");
      StringReplace(ligne, "\n", "");
      
      if(StringLen(ligne) < 10) continue;
      
      // Parser la ligne CSV
      string parties[];
      int nbParties = StringSplit(ligne, ',', parties);
      
      if(nbParties >= 7)
      {
         int idx = ArraySize(Trades);
         ArrayResize(Trades, idx + 1);
         
         Trades[idx].Symbole      = parties[0];
         Trades[idx].Type         = parties[1];
         Trades[idx].Entree       = StringToDouble(parties[2]);
         Trades[idx].TP           = StringToDouble(parties[3]);
         Trades[idx].SL           = StringToDouble(parties[4]);
         Trades[idx].Lots         = StringToDouble(parties[5]);
         Trades[idx].LotsOriginal = Trades[idx].Lots;
         Trades[idx].IsActive     = (int)StringToInteger(parties[6]) == 1;
         Trades[idx].MagicNumber  = MagicNumberBase + idx;
         Trades[idx].TradeExecute = false;
         Trades[idx].DerniereBougie = 0;
         
         if(Trades[idx].IsActive)
            TotalTrades++;
      }
   }
   
   FileClose(handle);
   return (ArraySize(Trades) > 0);
}

//+------------------------------------------------------------------+
//| Calculer le nombre de lots en fonction du risque                 |
//+------------------------------------------------------------------+
double CalculerLotsAuto(string symbole, double stopLoss)
{
   double lotsCalcules = LotsMin;
   
   // 1. Calcul basé sur le risque en % du compte
   double capital = AccountInfoDouble(ACCOUNT_BALANCE);
   double risqueEnDevise = capital * (RisquePourcent / 100.0);
   
   // Calculer la valeur du point pour ce symbole
   double tickValue = SymbolInfoDouble(symbole, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbole, SYMBOL_TRADE_TICK_SIZE);
   double pointSize = SymbolInfoDouble(symbole, SYMBOL_POINT);
   
   // Distance SL en points
   double distancePoints = stopLoss;
   
   // Calcul des lots basé sur le risque
   if(tickValue > 0 && distancePoints > 0)
   {
      double valeurPerteParLot = distancePoints * tickValue;
      
      if(valeurPerteParLot > 0)
      {
         lotsCalcules = risqueEnDevise / valeurPerteParLot;
         lotsCalcules = MathMin(lotsCalcules, LotsMax);
         lotsCalcules = MathMax(lotsCalcules, LotsMin);
      }
   }
   
   // 2. Si demandé, limiter par la marge disponible
   if(UtiliserMargePourMax)
   {
      double margeLibre = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double margeUtilisable = margeLibre * (PourcentageMargeMax / 100.0);
      
      // Estimation de la marge requise par lot
      double margeParLot = SymbolInfoDouble(symbole, SYMBOL_MARGIN_INITIAL);
      
      if(margeParLot > 0)
      {
         double lotsParMarge = margeUtilisable / margeParLot;
         lotsCalcules = MathMin(lotsCalcules, lotsParMarge);
      }
   }
   
   // Arrondir selon les règles du broker
   double stepLot = SymbolInfoDouble(symbole, SYMBOL_VOLUME_STEP);
   if(stepLot > 0)
   {
      lotsCalcules = MathFloor(lotsCalcules / stepLot) * stepLot;
   }
   
   lotsCalcules = MathMin(lotsCalcules, LotsMax);
   lotsCalcules = MathMax(lotsCalcules, LotsMin);
   
   if(ActiverLogsDetails)
   {
      Print("📊 CALCUL LOTS AUTO [", symbole, "]");
      Print("   Capital: ", DoubleToString(capital, 2));
      Print("   Risque: ", RisquePourcent, "% = ", DoubleToString(risqueEnDevise, 2));
      Print("   Distance SL: ", distancePoints, " points");
      Print("   Lots calculés: ", DoubleToString(lotsCalcules, 2));
   }
   
   return lotsCalcules;
}

//+------------------------------------------------------------------+
//| Calculer la distance SL en points                                |
//+------------------------------------------------------------------+
double CalculerDistanceSL(string symbole, double prixEntree, double stopLossPrice)
{
   if(stopLossPrice <= 0) return StopLossPoints; // Utiliser la valeur par défaut
   
   double distance = MathAbs(prixEntree - stopLossPrice);
   double pointSize = SymbolInfoDouble(symbole, SYMBOL_POINT);
   
   if(pointSize > 0)
      return distance / pointSize;
   else
      return StopLossPoints;
}

//+------------------------------------------------------------------+
//| Obtenir le prix d'entrée estimé selon le type                    |
//+------------------------------------------------------------------+
double GetEstimatedEntryPrice(string symbole, string type)
{
   if(type == "LONG")
      return SymbolInfoDouble(symbole, SYMBOL_ASK);
   else
      return SymbolInfoDouble(symbole, SYMBOL_BID);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Parcourir tous les trades configurés
   for(int i = 0; i < ArraySize(Trades); i++)
   {
      if(!Trades[i].IsActive) continue;
      if(Trades[i].TradeExecute) continue;
      
      // Vérifier si un trade similaire est déjà ouvert pour cet actif
      if(CountTradesForSymbol(Trades[i].Symbole, Trades[i].MagicNumber) > 0)
      {
         continue;
      }
      
      // Vérifier la condition pour ce trade
      VerifierConditionTrade(i);
   }
}

//+------------------------------------------------------------------+
//| Vérifier la condition pour un trade spécifique                   |
//+------------------------------------------------------------------+
void VerifierConditionTrade(int idx)
{
   string symbole = Trades[idx].Symbole;
   
   // Vérifier que le symbole existe
   if(!SymbolSelect(symbole, true))
   {
      if(ActiverLogsDetails)
         Print("⚠️ Symbole non disponible: ", symbole);
      return;
   }
   
   // Timeframe M5 fixe
   ENUM_TIMEFRAMES timeframe = PERIOD_M5;
   
   // Récupérer l'heure de la dernière bougie fermée
   datetime debut_bougie_fermee = iTime(symbole, timeframe, 1);
   
   // Si nouvelle bougie
   if(debut_bougie_fermee != Trades[idx].DerniereBougie)
   {
      Trades[idx].DerniereBougie = debut_bougie_fermee;
      
      // Récupérer le prix de clôture
      double prix_fermeture = iClose(symbole, timeframe, 1);
      
      if(ActiverLogsDetails)
      {
         datetime heure_fermeture = debut_bougie_fermee + (5 * 60);
         Print("───────────────────────────────────────────────────");
         Print("📌 [", symbole, "] Nouvelle bougie fermée");
         Print("   Heure: ", TimeToString(heure_fermeture));
         Print("   Clôture: ", DoubleToString(prix_fermeture, (int)SymbolInfoInteger(symbole, SYMBOL_DIGITS)));
         Print("   Seuil ", Trades[idx].Type, ": ", DoubleToString(Trades[idx].Entree, (int)SymbolInfoInteger(symbole, SYMBOL_DIGITS)));
      }
      
      // Vérifier la condition selon le type
      bool conditionValidee = false;
      
      if(Trades[idx].Type == "LONG")
      {
         if(prix_fermeture > Trades[idx].Entree)
         {
            conditionValidee = true;
            if(ActiverLogsDetails)
               Print("🎯 Condition LONG validée pour ", symbole);
         }
      }
      else if(Trades[idx].Type == "SHORT")
      {
         if(prix_fermeture < Trades[idx].Entree)
         {
            conditionValidee = true;
            if(ActiverLogsDetails)
               Print("🎯 Condition SHORT validée pour ", symbole);
         }
      }
      
      // Exécuter le trade si condition validée
      if(conditionValidee)
      {
         // Recalculer les lots si l'option est activée
         if(CalculAutoLots)
         {
            // Distance SL en points
            double prixEntreeEstime = GetEstimatedEntryPrice(symbole, Trades[idx].Type);
            double distanceSL = CalculerDistanceSL(symbole, prixEntreeEstime, Trades[idx].SL);
            
            if(distanceSL > 0)
            {
               double lotsAuto = CalculerLotsAuto(symbole, distanceSL);
               Trades[idx].Lots = lotsAuto;
            }
            else
            {
               Print("⚠️ Impossible de calculer la distance SL, utilisation des lots du CSV");
               Trades[idx].Lots = Trades[idx].LotsOriginal;
            }
         }
         
         ExecuteTrade(idx, prix_fermeture);
         Trades[idx].TradeExecute = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Exécuter un trade                                                |
//+------------------------------------------------------------------+
void ExecuteTrade(int idx, double prix_trigger)
{
   string symbole = Trades[idx].Symbole;
   string type = Trades[idx].Type;
   double lots = Trades[idx].Lots;
   double tp = Trades[idx].TP;
   double sl = Trades[idx].SL;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   // Vérifier la marge
   double marge_libre = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marge_requise = lots * SymbolInfoDouble(symbole, SYMBOL_MARGIN_INITIAL);
   
   if(marge_libre < marge_requise)
   {
      Print("❌ [", symbole, "] Marge insuffisante!");
      Print("   Marge libre: ", DoubleToString(marge_libre, 2));
      Print("   Marge requise: ", DoubleToString(marge_requise, 2));
      
      // Tentative de réduction des lots
      if(CalculAutoLots && lots > LotsMin)
      {
         double lotsReduits = lots * 0.8;
         lotsReduits = MathMax(lotsReduits, LotsMin);
         double stepLot = SymbolInfoDouble(symbole, SYMBOL_VOLUME_STEP);
         if(stepLot > 0)
            lotsReduits = MathFloor(lotsReduits / stepLot) * stepLot;
         
         Print("🔄 Tentative avec lots réduits: ", DoubleToString(lotsReduits, 2));
         Trades[idx].Lots = lotsReduits;
         
         // Recalculer la marge
         marge_requise = lotsReduits * SymbolInfoDouble(symbole, SYMBOL_MARGIN_INITIAL);
         if(marge_libre >= marge_requise)
         {
            lots = lotsReduits;
            Print("✅ Lots réduits acceptés: ", DoubleToString(lots, 2));
         }
         else
         {
            Print("❌ Marge toujours insuffisante, abandon du trade");
            return;
         }
      }
      else
      {
         return;
      }
   }
   
   // Configuration selon le type
   if(type == "LONG")
   {
      request.action = TRADE_ACTION_DEAL;
      request.symbol = symbole;
      request.volume = lots;
      request.type = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(symbole, SYMBOL_ASK);
      if(tp > 0) request.tp = tp;
      if(sl > 0) request.sl = sl;
      request.deviation = Slippage;
      request.magic = Trades[idx].MagicNumber;
      request.type_filling = ORDER_FILLING_FOK;
      request.comment = (CalculAutoLots ? "AutoLots " : "Fixed ") + type + " @" + DoubleToString(prix_trigger, 0);
   }
   else // SHORT
   {
      request.action = TRADE_ACTION_DEAL;
      request.symbol = symbole;
      request.volume = lots;
      request.type = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(symbole, SYMBOL_BID);
      if(tp > 0) request.tp = tp;
      if(sl > 0) request.sl = sl;
      request.deviation = Slippage;
      request.magic = Trades[idx].MagicNumber;
      request.type_filling = ORDER_FILLING_FOK;
      request.comment = (CalculAutoLots ? "AutoLots " : "Fixed ") + type + " @" + DoubleToString(prix_trigger, 0);
   }
   
   Print("═══════════════════════════════════════════════════════");
   Print("🚀 EXÉCUTION TRADE");
   Print("   Actif    : ", symbole);
   Print("   Type     : ", type);
   Print("   Lots     : ", lots, (CalculAutoLots ? " (calculé auto)" : " (fixe)"));
   Print("   Entrée   : ", request.price);
   Print("   TP       : ", tp);
   Print("   SL       : ", sl);
   Print("   Trigger  : ", prix_trigger);
   Print("═══════════════════════════════════════════════════════");
   
   bool envoye = OrderSend(request, result);
   
   if(envoye)
   {
      Print("✅✅✅ TRADE EXÉCUTÉ AVEC SUCCÈS ! ✅✅✅");
      Print("   Ticket: ", result.order);
      Print("   Prix entrée: ", result.price);
      Print("   Lots exécutés: ", result.volume);
      
      // Alerte visuelle et sonore
      Alert("🔔 Trade ", type, " sur ", symbole, " @ ", DoubleToString(result.price, (int)SymbolInfoInteger(symbole, SYMBOL_DIGITS)), " | Lots: ", DoubleToString(result.volume, 2));
      PlaySound("alert.wav");
   }
   else
   {
      Print("❌ ERREUR: ", result.retcode, " - ", GetErrorDescription(result.retcode));
   }
}

//+------------------------------------------------------------------+
//| Compter les trades ouverts pour un symbole                       |
//+------------------------------------------------------------------+
int CountTradesForSymbol(string symbole, int magic)
{
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbole && 
            PositionGetInteger(POSITION_MAGIC) == magic)
         {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Description des erreurs                                          |
//+------------------------------------------------------------------+
string GetErrorDescription(int code)
{
   switch(code)
   {
      case 10004: return "Requête invalide";
      case 10006: return "Volume incorrect";
      case 10007: return "Prix incorrect";
      case 10008: return "Slippage trop élevé";
      case 10009: return "Marge insuffisante";
      case 10010: return "Marché fermé";
      case 10011: return "Trade désactivé";
      case 10012: return "Délai d'attente dépassé";
      case 10013: return "Connexion perdue";
      default: return "Erreur code: " + IntegerToString(code);
   }
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("🔴 MULTI TRADE MANAGER V2 - ARRÊTÉ");
}
//+------------------------------------------------------------------+
