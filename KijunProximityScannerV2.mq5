//+------------------------------------------------------------------+
//|                                                    KijunScanner |
//|                                                                  |
//|                                              Copyright 2026 DLHR     |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI Réunionnais"
#property version   "1.00"
#property strict
#property description "EA qui scanne tous les actifs du Market Watch"
#property description "et détecte ceux proches de leur Kijun Sen"

//+------------------------------------------------------------------+
//| Paramètres d'entrée                                             |
//+------------------------------------------------------------------+
input double KijunDistancePercent = 0.5;      // Distance max en % du Kijun
input int    KijunPeriod = 26;                // Période Kijun Sen
input int    CheckInterval = 10;              // Intervalle de scan (secondes)
input bool   EnableAlerts = true;             // Activer les alertes
input bool   EnableSound = true;              // Activer le son
input bool   EnableNotification = false;      // Activer notifications mobile
input string SoundFile = "alert.wav";         // Fichier son

//+------------------------------------------------------------------+
//| Variables globales                                              |
//+------------------------------------------------------------------+
datetime lastCheckTime = 0;
string detectedSymbols[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Kijun Scanner EA initialisé");
   Print("Intervalle de scan: ", CheckInterval, " secondes");
   CreateButton();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ArrayFree(detectedSymbols);
   ObjectDelete(0, "btnScan");
   Print("Kijun Scanner EA arrêté");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Vérifier l'intervalle de scan
   if(TimeCurrent() - lastCheckTime < CheckInterval)
      return;
      
   lastCheckTime = TimeCurrent();
   ScanAllSymbols();
}

//+------------------------------------------------------------------+
//| Fonction de scan des symboles                                    |
//+------------------------------------------------------------------+
void ScanAllSymbols()
{
   int totalSymbols = SymbolsTotal(true);
   string newDetected[];
   int detectedCount = 0;
   
   Print("Scan de ", totalSymbols, " symboles à ", TimeToString(TimeCurrent(), TIME_SECONDS));
   
   for(int i = 0; i < totalSymbols; i++)
   {
      string symbol = SymbolName(i, true);
      
      // Vérifier si le symbole est accessible
      if(!CheckSymbol(symbol))
         continue;
      
      // Vérifier la distance par rapport au Kijun
      bool isNearKijun = CheckKijunDistance(symbol);
      
      if(isNearKijun)
      {
         ArrayResize(newDetected, detectedCount + 1);
         newDetected[detectedCount] = symbol;
         detectedCount++;
         
         Print("DÉTECTÉ: ", symbol, " - Proche du Kijun Sen");
         
         if(EnableAlerts)
            SendAlerts(symbol);
      }
   }
   
   // Mettre à jour la liste des symboles détectés
   ArrayResize(detectedSymbols, detectedCount);
   for(int i = 0; i < detectedCount; i++)
   {
      detectedSymbols[i] = newDetected[i];
   }
   
   Print("Scan terminé. ", detectedCount, " symbole(s) détecté(s)");
}

//+------------------------------------------------------------------+
//| Vérification de la distance au Kijun                            |
//+------------------------------------------------------------------+
bool CheckKijunDistance(string symbol)
{
   // Obtenir les données Ichimoku
   int handle = iIchimoku(symbol, PERIOD_CURRENT, KijunPeriod, 52, 26);
   
   if(handle == INVALID_HANDLE)
   {
      Print("Erreur: Impossible de créer handle Ichimoku pour ", symbol);
      return false;
   }
   
   // Tableaux pour les données
   double tenkanSen[];
   double kijunSen[];
   double senkouSpanA[];
   double senkouSpanB[];
   double chinkouSpan[];
   
   ArraySetAsSeries(tenkanSen, true);
   ArraySetAsSeries(kijunSen, true);
   ArraySetAsSeries(senkouSpanA, true);
   ArraySetAsSeries(senkouSpanB, true);
   ArraySetAsSeries(chinkouSpan, true);
   
   // Copier les données
   ResetLastError();
   int copied = CopyBuffer(handle, 0, 1, 2, tenkanSen);     // Tenkan Sen
   if(copied < 0) Print("Erreur copie Tenkan: ", GetLastError());
   
   copied = CopyBuffer(handle, 1, 1, 2, kijunSen);         // Kijun Sen
   if(copied < 0) Print("Erreur copie Kijun: ", GetLastError());
   
   copied = CopyBuffer(handle, 2, 1, 2, senkouSpanA);      // Senkou Span A
   copied = CopyBuffer(handle, 3, 1, 2, senkouSpanB);      // Senkou Span B
   copied = CopyBuffer(handle, 4, 1, 2, chinkouSpan);      // Chinkou Span
   
   // Libérer le handle
   IndicatorRelease(handle);
   
   // Vérifier si les données sont valides
   if(ArraySize(kijunSen) < 1 || kijunSen[0] <= 0)
      return false;
   
   // Obtenir le prix actuel
   double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
   double kijunValue = kijunSen[0];
   
   // Vérifier si le Kijun est valide
   if(kijunValue <= 0)
      return false;
   
   // Calculer la distance en %
   double distance = MathAbs(currentPrice - kijunValue) / kijunValue * 100;
   
   // Vérifier si dans la zone définie
   return (distance <= KijunDistancePercent);
}

//+------------------------------------------------------------------+
//| Vérification de la disponibilité du symbole                     |
//+------------------------------------------------------------------+
bool CheckSymbol(string symbol)
{
   // Activer le symbole si nécessaire
   if(!SymbolInfoInteger(symbol, SYMBOL_SELECT))
   {
      if(!SymbolSelect(symbol, true))
      {
         Print("Impossible de sélectionner: ", symbol);
         return false;
      }
   }
   
   // Forcer le rafraîchissement des données
   if(!SeriesInfoInteger(symbol, PERIOD_CURRENT, SERIES_SYNCHRONIZED))
   {
      // Attendre un peu pour la synchronisation
      Sleep(10);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Envoi des alertes                                               |
//+------------------------------------------------------------------+
void SendAlerts(string symbol)
{
   string message = StringFormat(
      "%s - Prix proche du Kijun Sen (%.1f%%)",
      symbol,
      KijunDistancePercent
   );
   
   // Alerte popup
   if(EnableAlerts)
      Alert(message);
   
   // Son
   if(EnableSound)
   {
      PlaySound(SoundFile);
   }
   
   // Notification mobile
   if(EnableNotification)
   {
      SendNotification(message);
   }
}

//+------------------------------------------------------------------+
//| Fonction de test rapide - appuyez sur le bouton                 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "btnScan")
      {
         Print("Scan manuel demandé");
         ScanAllSymbols();
         ObjectSetInteger(0, "btnScan", OBJPROP_STATE, false);
      }
   }
}

//+------------------------------------------------------------------+
//| Création du bouton de scan manuel                               |
//+------------------------------------------------------------------+
void CreateButton()
{
   if(ObjectFind(0, "btnScan") < 0)
   {
      ObjectCreate(0, "btnScan", OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, "btnScan", OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, "btnScan", OBJPROP_YDISTANCE, 10);
      ObjectSetInteger(0, "btnScan", OBJPROP_XSIZE, 100);
      ObjectSetInteger(0, "btnScan", OBJPROP_YSIZE, 30);
      ObjectSetString(0, "btnScan", OBJPROP_TEXT, "Scan Manuel");
      ObjectSetString(0, "btnScan", OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, "btnScan", OBJPROP_FONTSIZE, 12);
      ObjectSetInteger(0, "btnScan", OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, "btnScan", OBJPROP_BGCOLOR, clrBlue);
      ObjectSetInteger(0, "btnScan", OBJPROP_BORDER_COLOR, clrWhite);
      ObjectSetInteger(0, "btnScan", OBJPROP_BACK, false);
      ObjectSetInteger(0, "btnScan", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, "btnScan", OBJPROP_HIDDEN, false);
   }
}
