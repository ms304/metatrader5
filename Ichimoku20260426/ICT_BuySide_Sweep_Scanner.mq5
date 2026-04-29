//+------------------------------------------------------------------+
//|                                        ICT_BuySweep_Scanner.mq5  |
//|                   Détection Sweep High + Retour Baissier (ICT)   |
//|                                  Version stable - BuySide        |
//+------------------------------------------------------------------+
#property copyright "ICT Scanner"
#property version   "1.20"
#property strict

//+------------------------------------------------------------------+
//| PARAMETRES INPUT                                                 |
//+------------------------------------------------------------------+
input string   FichierSortie = "ICT_BuySweep_Detections.txt";
input bool     AfficherLogs = true;           // Afficher logs détaillés
input int      ProfondeurBalayage = 3;        // Nb bougies avant pour sweep

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
   // Supprimer les anciens objets graphiques
   for(int i = 0; i < ObjectsTotal(0); i++)
   {
      string nom = ObjectName(0, i);
      if(StringFind(nom, "ICT_Signal_") == 0)
      {
         datetime tempsObjet = (datetime)ObjectGetInteger(0, nom, OBJPROP_TIME);
         if(TimeCurrent() - tempsObjet > 60) // Supprimer après 60 secondes
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
   
   if(AfficherLogs)
   {
      Print("");
      Print("╔════════════════════════════════════════════════════════════════════════════════╗");
      Print("║                    SCAN ICT - SWEEP BUYSIDE LIQUIDITY                          ║");
      Print("║                          ", TimeToString(TimeCurrent()), "                          ║");
      Print("╚════════════════════════════════════════════════════════════════════════════════╝");
      Print("");
   }
   
   for(int i = 0; i < total; i++)
   {
      string symbole = SymbolName(i, true);
      if(symbole == "") continue;
      
      // Vérifier si le symbole est disponible
      if(!SymbolSelect(symbole, true))
      {
         if(AfficherLogs) Print("❌ ", symbole, " -> Impossible de selectionner le symbole");
         continue;
      }
      
      // Récupérer N bougies pour analyse
      MqlRates bougies[];
      ArraySetAsSeries(bougies, true);
      
      int nbBougies = ProfondeurBalayage + 2;
      if(CopyRates(symbole, PERIOD_D1, 0, nbBougies, bougies) < nbBougies)
      {
         if(AfficherLogs) Print("❌ ", symbole, " -> Impossible de recuperer les donnees");
         continue;
      }
      
      // Bougies actuelles
      MqlRates actuelle = bougies[0];
      MqlRates precedente = bougies[1];
      
      // Trouver le plus HAUT sur les N dernières bougies (sauf la bougie en cours)
      double highestHigh = precedente.high;
      int highestIndex = 1;
      
      for(int j = 1; j <= ProfondeurBalayage; j++)
      {
         if(bougies[j].high > highestHigh)
         {
            highestHigh = bougies[j].high;
            highestIndex = j;
         }
      }
      
      double lowestLow = precedente.low;
      for(int j = 1; j <= ProfondeurBalayage; j++)
      {
         if(bougies[j].low < lowestLow)
            lowestLow = bougies[j].low;
      }
      
      // === CRITÈRES ICT POUR SWEEP BUYSIDE ===
      
      // 1. Sweep du plus haut : La bougie en cours a un plus haut > plus haut des N bougies précédentes
      bool sweepHigh = (actuelle.high > highestHigh);
      
      // 2. Bougie BAISSIÈRE (close < open)
      bool bougieBaissiere = (actuelle.close < actuelle.open);
      
      // 3. Retour BAISSIER : Le prix a balayé le plus haut mais refermé dans le 1/3 inférieur de la bougie
      double rangeBougie = actuelle.high - actuelle.low;
      double closeDeltaFromHigh = actuelle.high - actuelle.close;
      bool retourBaissier = false;
      if(rangeBougie > 0)
         retourBaissier = (closeDeltaFromHigh > (rangeBougie * 0.66));
      
      // 4. Fermeture en dessous du plus haut précédent (confirmation du sweep)
      bool closeBelowHigh = (actuelle.close < highestHigh);
      
      // 5. Wick significatif en HAUT (rejet de liquidité côté acheteur)
      double wickHaut = (actuelle.high > actuelle.close) ? (actuelle.high - actuelle.close) : 0;
      bool rejectionHaut = (wickHaut > rangeBougie * 0.30);
      
      // CONDITION FINALE ICT BUYSIDE SWEEP
      bool conditionICT = (sweepHigh && bougieBaissiere && retourBaissier && closeBelowHigh);
      
      if(AfficherLogs)
      {
         AfficherDetails(symbole, actuelle, precedente, lowestLow, highestHigh, 
                        sweepHigh, bougieBaissiere, retourBaissier, 
                        rejectionHaut, conditionICT);
      }
      
      if(conditionICT)
      {
         // Vérifier si on a déjà alerté pour ce symbole
         bool dejaAlerte = false;
         for(int a = 0; a < ArraySize(symbolesAlertes); a++)
         {
            if(symbolesAlertes[a] == symbole)
            {
               // Vérifier si l'alerte date de moins de 1 heure
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
            
            // === SYSTEME D'ALERTE ===
            // Alerte popup
            Alert("🔔 ICT BUYSIDE SWEEP DETECTE: ", symbole);
            
            // Alerte sonore
            PlaySound("alert.wav");
            
            // Notification push (si configurée dans MT5)
            string notification = symbole + " - Buyside Sweep Detecte | Prix: " + 
                                 DoubleToString(actuelle.close, (int)SymbolInfoInteger(symbole, SYMBOL_DIGITS));
            SendNotification(notification);
            
            // Afficher sur le chart
            AfficherSignalSurChart(symbole, actuelle.close);
            
            // Enregistrer l'alerte pour éviter les doublons
            int taille = ArraySize(symbolesAlertes);
            ArrayResize(symbolesAlertes, taille + 1);
            ArrayResize(dernierAlerte, taille + 1);
            symbolesAlertes[taille] = symbole;
            dernierAlerte[taille] = TimeCurrent();
            
            if(AfficherLogs)
               Print("  🟢 NOUVEAU SIGNAL: ", symbole, " ajoute aux alertes");
         }
         else
         {
            if(AfficherLogs)
               Print("  ⏱️ ", symbole, " deja alerte il y a moins d'1 heure - Ignore");
         }
      }
   }
   
   if(AfficherLogs && compte > 0)
   {
      AfficherResume(total, compte);
   }
   else if(AfficherLogs && compte == 0)
   {
      Print("");
      Print("╔════════════════════════════════════════════════════════════════════════════════╗");
      Print("║                          RESUME DU SCAN ICT - BUYSIDE                          ║");
      Print("╠════════════════════════════════════════════════════════════════════════════════╣");
      Print("║  Total symboles scannes : ", total);
      Print("║  Sweep buyside detectes : 0");
      Print("║  Aucun signal pour le moment");
      Print("╚════════════════════════════════════════════════════════════════════════════════╝");
      Print("");
   }
   
   EcrireFichier(compte);
}

//+------------------------------------------------------------------+
//| Affichage détaillé des conditions - BUYSIDE                      |
//+------------------------------------------------------------------+
void AfficherDetails(string symbole, MqlRates &actuelle, MqlRates &precedente, 
                     double lowestLow, double highestHigh,
                     bool sweepHigh, bool bougieBaissiere, bool retourBaissier,
                     bool rejectionHaut, bool conditionICT)
{
   int digits = (int)SymbolInfoInteger(symbole, SYMBOL_DIGITS);
   
   Print("");
   Print("┌─────────────────────────────────────────────────────────────────────────────┐");
   Print("│ ICT BUYSIDE ANALYSIS - ", symbole);
   Print("├─────────────────────────────────────────────────────────────────────────────┤");
   Print("│ BOUGIE ACTUELLE (", TimeToString(actuelle.time, TIME_DATE), ")");
   Print("│   Open  : ", DoubleToString(actuelle.open, digits));
   Print("│   High  : ", DoubleToString(actuelle.high, digits));
   Print("│   Low   : ", DoubleToString(actuelle.low, digits));
   Print("│   Close : ", DoubleToString(actuelle.close, digits));
   Print("│");
   Print("│ BOUGIE PRECEDENTE (", TimeToString(precedente.time, TIME_DATE), ")");
   Print("│   High  : ", DoubleToString(precedente.high, digits));
   Print("│   Low   : ", DoubleToString(precedente.low, digits));
   Print("│");
   Print("│ NIVEAUX ICT (", ProfondeurBalayage, " bougies):");
   Print("│   Lowest Low  : ", DoubleToString(lowestLow, digits));
   Print("│   Highest High: ", DoubleToString(highestHigh, digits));
   Print("│");
   Print("│ CONDITIONS ICT BUYSIDE SWEEP :");
   Print("│   1. Sweep Buyside (High > HighestHigh) : ", sweepHigh ? "✅ OUI" : "❌ NON");
   Print("│      (", DoubleToString(actuelle.high, digits), " > ", DoubleToString(highestHigh, digits), ")");
   Print("│");
   Print("│   2. Bougie baissiere (Close < Open) : ", bougieBaissiere ? "✅ OUI" : "❌ NON");
   Print("│      (", DoubleToString(actuelle.close, digits), " < ", DoubleToString(actuelle.open, digits), ")");
   Print("│");
   Print("│   3. Retour dans 66% inferieur : ", retourBaissier ? "✅ OUI" : "❌ NON");
   double rangeBougie = actuelle.high - actuelle.low;
   double closeDeltaFromHigh = actuelle.high - actuelle.close;
   if(rangeBougie > 0)
   {
      double pourcentage = (closeDeltaFromHigh / rangeBougie) * 100;
      Print("│      (Close a ", DoubleToString(pourcentage, 1), "% du haut de la bougie)");
   }
   Print("│");
   Print("│   4. Close < HighestHigh : ", closeBelowHighCheck(actuelle.close, highestHigh) ? "✅ OUI" : "❌ NON");
   Print("│      (", DoubleToString(actuelle.close, digits), " < ", DoubleToString(highestHigh, digits), ")");
   Print("│");
   Print("│   5. Rejection wick haut : ", rejectionHaut ? "✅ OUI" : "❌ NON");
   Print("│");
   Print("│ 🎯 BUYSIDE SWEEP ICT DETECTE : ", conditionICT ? "🟢 OUI" : "🔴 NON");
   
   if(conditionICT)
   {
      Print("│");
      Print("│ 💡 RECOMMANDATION TRADE:");
      Print("│    - Entry: Break of structure baissier");
      Print("│    - Stop Loss: Au-dessus du sweep (", DoubleToString(actuelle.high, digits), ")");
      Print("│    - Take Profit 1: ", DoubleToString(lowestLow, digits));
      Print("│    - Take Profit 2: ", DoubleToString(lowestLow - (highestHigh - lowestLow), digits));
   }
   
   Print("└─────────────────────────────────────────────────────────────────────────────┘");
}

//+------------------------------------------------------------------+
//| Vérifier si close < highestHigh avec marge de sécurité           |
//+------------------------------------------------------------------+
bool closeBelowHighCheck(double close, double highestHigh)
{
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (close < highestHigh - (pointValue * 2)); // Marge de 2 points
}

//+------------------------------------------------------------------+
//| Affichage du résumé                                              |
//+------------------------------------------------------------------+
void AfficherResume(int total, int compte)
{
   Print("");
   Print("╔════════════════════════════════════════════════════════════════════════════════╗");
   Print("║                          RESUME DU SCAN ICT - BUYSIDE                           ║");
   Print("╠════════════════════════════════════════════════════════════════════════════════╣");
   Print("║  Total symboles scannes : ", total);
   Print("║  Sweep buyside detectes : ", compte);
   
   if(compte > 0)
   {
      string liste = "";
      for(int i = 0; i < compte; i++)
      {
         if(i > 0) liste += ", ";
         liste += symbolesDetectes[i];
      }
      Print("║  Actifs detectes : ", liste);
      Print("║");
      Print("║  ⚡ ALERTES ENVOYEES : Popup + Son + Push Notification");
   }
   
   Print("╚════════════════════════════════════════════════════════════════════════════════╝");
   Print("");
}

//+------------------------------------------------------------------+
//| Afficher un signal sur le graphique                              |
//+------------------------------------------------------------------+
void AfficherSignalSurChart(string symbole, double prix)
{
   string objName = "ICT_Signal_" + symbole + "_" + IntegerToString(TimeCurrent());
   
   // Créer un label sur le graphique actuel
   if(ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, 30);
      ObjectSetString(0, objName, OBJPROP_TEXT, "🔔 ICT BUYSIDE: " + symbole + " @ " + DoubleToString(prix, _Digits));
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 11);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clrOrange);  // Orange pour buyside
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      
      // Ajouter un timestamp pour nettoyage automatique
      ObjectSetInteger(0, objName, OBJPROP_TIME, TimeCurrent());
   }
}

//+------------------------------------------------------------------+
//| Ecrire le fichier avec détails ICT - BUYSIDE                     |
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
   FileWrite(handle, "Condition ICT Sweep Buyside:");
   FileWrite(handle, "1. Plus haut actuel > Plus haut des ", ProfondeurBalayage, " bougies precedentes");
   FileWrite(handle, "2. Bougie en cours baissiere (close < open)");
   FileWrite(handle, "3. Retour dans les 66% inferieurs de la bougie");
   FileWrite(handle, "4. Fermeture < plus haut sweep");
   FileWrite(handle, "5. Wick significatif en haut (rejection)");
   FileWrite(handle, "");
   FileWrite(handle, "-----------------------------------------");
   
   if(nbDetections == 0)
   {
      FileWrite(handle, "Aucun sweep buyside detecte sur ce scan");
   }
   else
   {
      FileWrite(handle, "Nombre de sweeps buyside detectes: ", nbDetections);
      FileWrite(handle, "");
      FileWrite(handle, "LISTE DES ACTIFS:");
      FileWrite(handle, "");
      
      for(int i = 0; i < nbDetections; i++)
      {
         FileWrite(handle, IntegerToString(i+1) + ". " + symbolesDetectes[i]);
      }
      
      FileWrite(handle, "");
      FileWrite(handle, "⚠️ Note: Les alertes sont limitees a 1 par symbole par heure");
   }
   
   FileWrite(handle, "=========================================");
   FileClose(handle);
   
   if(nbDetections > 0 && AfficherLogs)
      Print("📁 Fichier mis a jour: ", FichierSortie, " (", nbDetections, " actifs)");
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Nettoyer les objets graphiques
   for(int i = 0; i < ObjectsTotal(0); i++)
   {
      string nom = ObjectName(0, i);
      if(StringFind(nom, "ICT_Signal_") == 0)
         ObjectDelete(0, nom);
   }
   
   // Supprimer le timer si actif
   EventKillTimer();
   
   Print("🛑 Scanner ICT Buyside arrete - Dernier scan: ", TimeToString(TimeCurrent()));
   Print("📊 Total alertes envoyees: ", ArraySize(symbolesAlertes));
}
//+------------------------------------------------------------------+
