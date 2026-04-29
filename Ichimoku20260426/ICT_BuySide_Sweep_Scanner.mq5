//+------------------------------------------------------------------+
//|                                        ICT_BuySweep_Scanner.mq5  |
//|                   Détection Sweep High + Retour Baissier (ICT)   |
//|                                  Version minimal logs - BuySide  |
//+------------------------------------------------------------------+
#property copyright "ICT Scanner"
#property version   "1.21"
#property strict

//+------------------------------------------------------------------+
//| PARAMETRES INPUT                                                 |
//+------------------------------------------------------------------+
input string   FichierSortie = "ICT_BuySweep_Detections.txt";
input bool     ActiverLogsMinimaux = true;      // Activer logs minimaux (seulement détections)
input int      ProfondeurBalayage = 3;          // Nb bougies avant pour sweep

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                               |
//+------------------------------------------------------------------+
string symbolesDetectes[];
datetime dernierScan = 0;
string symbolesAlertes[];  // Pour éviter les doublons d'alertes
datetime dernierAlerte[];  // Timestamp de la dernière alerte par symbole

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // Scanner toutes les 30 secondes
   if(TimeCurrent() - dernierScan < 30)
      return;
      
   dernierScan = TimeCurrent();
   ScannerICT();
}

//+------------------------------------------------------------------+
//| OnTimer - Nettoyer les objets graphiques                         |
//+------------------------------------------------------------------+
void OnTimer()
{
   for(int i = 0; i < ObjectsTotal(0); i++)
   {
      string nom = ObjectName(0, i);
      if(StringFind(nom, "ICT_Signal_") == 0)
      {
         datetime tempsObjet = (datetime)ObjectGetInteger(0, nom, OBJPROP_TIME);
         if(TimeCurrent() - tempsObjet > 3600) // Supprimer après 1 heure
            ObjectDelete(0, nom);
      }
   }
}

//+------------------------------------------------------------------+
//| Scanner principal avec concepts ICT - BUYSIDE SWEEP              |
//+------------------------------------------------------------------+
void ScannerICT()
{
   int total = SymbolsTotal(true);
   int compte = 0;
   
   ArrayResize(symbolesDetectes, 0);
   
   for(int i = 0; i < total; i++)
   {
      string symbole = SymbolName(i, true);
      if(symbole == "") continue;
      
      if(!SymbolSelect(symbole, true))
         continue;
      
      MqlRates bougies[];
      ArraySetAsSeries(bougies, true);
      
      int nbBougies = ProfondeurBalayage + 2;
      if(CopyRates(symbole, PERIOD_D1, 0, nbBougies, bougies) < nbBougies)
         continue;
      
      MqlRates actuelle = bougies[0];
      MqlRates precedente = bougies[1];
      
      // Trouver le plus HAUT sur les N dernières bougies
      double highestHigh = precedente.high;
      
      for(int j = 1; j <= ProfondeurBalayage; j++)
      {
         if(bougies[j].high > highestHigh)
            highestHigh = bougies[j].high;
      }
      
      double lowestLow = precedente.low;
      for(int j = 1; j <= ProfondeurBalayage; j++)
      {
         if(bougies[j].low < lowestLow)
            lowestLow = bougies[j].low;
      }
      
      // === CRITÈRES ICT POUR SWEEP BUYSIDE ===
      bool sweepHigh = (actuelle.high > highestHigh);
      bool bougieBaissiere = (actuelle.close < actuelle.open);
      
      double rangeBougie = actuelle.high - actuelle.low;
      double closeDeltaFromHigh = actuelle.high - actuelle.close;
      bool retourBaissier = false;
      if(rangeBougie > 0)
         retourBaissier = (closeDeltaFromHigh > (rangeBougie * 0.66));
      
      bool closeBelowHigh = (actuelle.close < highestHigh);
      
      bool conditionICT = (sweepHigh && bougieBaissiere && retourBaissier && closeBelowHigh);
      
      if(conditionICT)
      {
         // Vérifier doublon d'alerte (1 par heure max)
         bool dejaAlerte = false;
         int idxExistant = -1;
         
         for(int a = 0; a < ArraySize(symbolesAlertes); a++)
         {
            if(symbolesAlertes[a] == symbole)
            {
               idxExistant = a;
               if(TimeCurrent() - dernierAlerte[a] < 3600)
               {
                  dejaAlerte = true;
                  break;
               }
            }
         }
         
         if(!dejaAlerte)
         {
            compte++;
            ArrayResize(symbolesDetectes, compte);
            symbolesDetectes[compte-1] = symbole;
            
            // === LOG DE DETECTION UNIQUE ===
            string detectionMsg = StringFormat("[BUYSIDE] %s - ICT Buyside Sweep | Prix: %s | %s",
                               symbole,
                               DoubleToString(actuelle.close, (int)SymbolInfoInteger(symbole, SYMBOL_DIGITS)),
                               TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS));
            
            Print(detectionMsg);
            
            // Alertes popup + son + push
            Alert("🔔 ICT BUYSIDE: ", symbole, " @ ", DoubleToString(actuelle.close, (int)SymbolInfoInteger(symbole, SYMBOL_DIGITS)));
            PlaySound("alert.wav");
            
            string notification = symbole + " - Buyside Sweep @ " + 
                                 DoubleToString(actuelle.close, (int)SymbolInfoInteger(symbole, SYMBOL_DIGITS));
            SendNotification(notification);
            
            AfficherSignalSurChart(symbole, actuelle.close);
            
            // Enregistrer l'alerte
            if(idxExistant >= 0)
            {
               symbolesAlertes[idxExistant] = symbole;
               dernierAlerte[idxExistant] = TimeCurrent();
            }
            else
            {
               int taille = ArraySize(symbolesAlertes);
               ArrayResize(symbolesAlertes, taille + 1);
               ArrayResize(dernierAlerte, taille + 1);
               symbolesAlertes[taille] = symbole;
               dernierAlerte[taille] = TimeCurrent();
            }
         }
      }
   }
   
   if(compte > 0)
   {
      EcrireFichier(compte);
      
      if(ActiverLogsMinimaux)
      {
         string liste = "";
         for(int i = 0; i < compte; i++)
         {
            if(i > 0) liste += ", ";
            liste += symbolesDetectes[i];
         }
         Print(StringFormat("[RESUME BUYSIDE] %d detection(s): %s", compte, liste));
      }
   }
}

//+------------------------------------------------------------------+
//| Afficher un signal sur le graphique                              |
//+------------------------------------------------------------------+
void AfficherSignalSurChart(string symbole, double prix)
{
   string objName = "ICT_Signal_" + symbole + "_" + IntegerToString(TimeCurrent());
   
   if(ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, 30);
      ObjectSetString(0, objName, OBJPROP_TEXT, "🔔 BUYSIDE: " + symbole + " @ " + DoubleToString(prix, _Digits));
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clrOrange);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      ObjectSetInteger(0, objName, OBJPROP_TIME, TimeCurrent());
   }
}

//+------------------------------------------------------------------+
//| Ecrire le fichier avec détails                                   |
//+------------------------------------------------------------------+
void EcrireFichier(int nbDetections)
{
   int handle = FileOpen(FichierSortie, FILE_WRITE | FILE_TXT);
   
   if(handle == INVALID_HANDLE)
   {
      Print("ERREUR: Impossible de creer le fichier ", FichierSortie);
      return;
   }
   
   FileWrite(handle, "=========================================");
   FileWrite(handle, "ICT BUYSIDE SWEEP DETECTIONS");
   FileWrite(handle, TimeToString(TimeCurrent()));
   FileWrite(handle, "=========================================");
   FileWrite(handle, "");
   FileWrite(handle, "Conditions ICT Sweep Buyside:");
   FileWrite(handle, "1. Plus haut actuel > Plus haut des ", ProfondeurBalayage, " bougies");
   FileWrite(handle, "2. Bougie baissiere (close < open)");
   FileWrite(handle, "3. Retour dans les 66% inferieurs");
   FileWrite(handle, "4. Fermeture < plus haut sweep");
   FileWrite(handle, "");
   FileWrite(handle, "-----------------------------------------");
   
   if(nbDetections == 0)
   {
      FileWrite(handle, "Aucun sweep buyside detecte");
   }
   else
   {
      FileWrite(handle, "Sweeps buyside: ", nbDetections);
      FileWrite(handle, "");
      FileWrite(handle, "LISTE:");
      FileWrite(handle, "");
      
      for(int i = 0; i < nbDetections; i++)
      {
         FileWrite(handle, IntegerToString(i+1) + ". " + symbolesDetectes[i]);
      }
      
      FileWrite(handle, "");
      FileWrite(handle, "⚠️ 1 alerte max/symbole/heure");
   }
   
   FileWrite(handle, "=========================================");
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < ObjectsTotal(0); i++)
   {
      string nom = ObjectName(0, i);
      if(StringFind(nom, "ICT_Signal_") == 0)
         ObjectDelete(0, nom);
   }
   
   EventKillTimer();
   
   if(ActiverLogsMinimaux)
      Print("🛑 Scanner Buyside arrete - Dernier scan: ", TimeToString(TimeCurrent()));
}
//+------------------------------------------------------------------+
