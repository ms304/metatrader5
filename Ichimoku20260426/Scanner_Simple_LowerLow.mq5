//+------------------------------------------------------------------+
//|                                         Scanner_Simple_LowerLow.mq5 |
//|                                     VERSION AVEC ARRAYSETASSERIES |
//+------------------------------------------------------------------+
#property copyright "Scanner Simple"
#property version   "1.00"
#property strict

input string   FichierSortie = "Actifs_detectes.txt";

string symbolesDetectes[];

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime dernierScan = 0;
   
   // Scanner toutes les 30 secondes
   if(TimeCurrent() - dernierScan < 30)
      return;
      
   dernierScan = TimeCurrent();
   Scanner();
}

//+------------------------------------------------------------------+
//| Fonction principale de scan                                      |
//+------------------------------------------------------------------+
void Scanner()
{
   int total = SymbolsTotal(true);
   int compte = 0;
   
   ArrayResize(symbolesDetectes, 0);
   
   Print("");
   Print("╔════════════════════════════════════════════════════════════════════════════════╗");
   Print("║                          SCAN DU ", TimeToString(TimeCurrent()), "                          ║");
   Print("╚════════════════════════════════════════════════════════════════════════════════╝");
   Print("");
   
   for(int i = 0; i < total; i++)
   {
      string symbole = SymbolName(i, true);
      if(symbole == "") continue;
      
      // Récupérer les 2 dernières bougies journalières
      MqlRates bougies[];
      
      // IMPORTANT: Forcer l'ordre série (index 0 = plus récent)
      ArraySetAsSeries(bougies, true);
      
      if(CopyRates(symbole, PERIOD_D1, 0, 2, bougies) < 2)
      {
         Print("❌ ", symbole, " -> Impossible de recuperer les donnees");
         continue;
      }
      
      // MAINTENANT : bougies[0] = bougie EN COURS (la plus récente)
      //             bougies[1] = bougie PRECEDENTE (hier)
      
      double openActuel   = bougies[0].open;
      double closeActuel  = bougies[0].close;
      double hautActuel   = bougies[0].high;
      double basActuel    = bougies[0].low;
      datetime tempsActuel = bougies[0].time;
      
      double openPrecedent   = bougies[1].open;
      double closePrecedent  = bougies[1].close;
      double hautPrecedent   = bougies[1].high;
      double basPrecedent    = bougies[1].low;
      datetime tempsPrecedent = bougies[1].time;
      
      // CONDITION 1: La bougie en cours est HAUSSIERE (close > open)
      bool estHaussiere = (closeActuel > openActuel);
      
      // CONDITION 2: Le plus bas actuel est PLUS BAS que le precedent
      bool lowerLow = (basActuel < basPrecedent);
      
      // AFFICHAGE DETAILLE POUR CHAQUE SYMBOLE
      Print("");
      Print("┌─────────────────────────────────────────────────────────────────────────────┐");
      Print("│ SYMBOLE : ", symbole);
      Print("├─────────────────────────────────────────────────────────────────────────────┤");
      Print("│ BOUGIE EN COURS (", TimeToString(tempsActuel, TIME_DATE), ")");
      Print("│   Open  : ", DoubleToString(openActuel, _Digits));
      Print("│   Close : ", DoubleToString(closeActuel, _Digits));
      Print("│   High  : ", DoubleToString(hautActuel, _Digits));
      Print("│   Low   : ", DoubleToString(basActuel, _Digits));
      Print("│");
      Print("│ BOUGIE PRECEDENTE (", TimeToString(tempsPrecedent, TIME_DATE), ")");
      Print("│   Open  : ", DoubleToString(openPrecedent, _Digits));
      Print("│   Close : ", DoubleToString(closePrecedent, _Digits));
      Print("│   High  : ", DoubleToString(hautPrecedent, _Digits));
      Print("│   Low   : ", DoubleToString(basPrecedent, _Digits));
      Print("│");
      Print("│ VERIFICATION DES CONDITIONS :");
      Print("│   1. Bougie HAUSSIERE ? ", estHaussiere ? "✅ OUI" : "❌ NON");
      Print("│      (Close ", DoubleToString(closeActuel, _Digits), " > Open ", DoubleToString(openActuel, _Digits), ") = ", estHaussiere);
      Print("│");
      Print("│   2. Lower Low ? ", lowerLow ? "✅ OUI" : "❌ NON");
      Print("│      (Bas actuel ", DoubleToString(basActuel, _Digits), " < Bas precedent ", DoubleToString(basPrecedent, _Digits), ") = ", lowerLow);
      Print("│");
      
      if(estHaussiere && lowerLow)
      {
         compte++;
         ArrayResize(symbolesDetectes, compte);
         symbolesDetectes[compte-1] = symbole;
         Print("│ 🟢 RESULTAT : DETECTE !!! 🟢");
      }
      else
      {
         Print("│ 🔴 RESULTAT : NON DETECTE");
         if(!estHaussiere && !lowerLow)
            Print("│     (Les 2 conditions sont fausses)");
         else if(!estHaussiere)
            Print("│     (Seulement condition 1 fausse)");
         else if(!lowerLow)
            Print("│     (Seulement condition 2 fausse)");
      }
      Print("└─────────────────────────────────────────────────────────────────────────────┘");
   }
   
   Print("");
   Print("╔════════════════════════════════════════════════════════════════════════════════╗");
   Print("║                          RESUME DU SCAN                                         ║");
   Print("╠════════════════════════════════════════════════════════════════════════════════╣");
   Print("║  Total symboles scannes : ", total);
   Print("║  Symboles detectes      : ", compte);
   if(compte > 0)
   {
      string liste = "";
      for(int i = 0; i < compte; i++)
      {
         if(i > 0) liste += ", ";
         liste += symbolesDetectes[i];
      }
      Print("║  Liste : ", liste);
   }
   else
   {
      Print("║  Aucun symbole ne remplit les conditions");
   }
   Print("╚════════════════════════════════════════════════════════════════════════════════╝");
   Print("");
   
   // Ecrire dans le fichier
   EcrireFichier(compte);
}

//+------------------------------------------------------------------+
//| Ecrire le fichier texte                                          |
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
   FileWrite(handle, "ACTIFS DETECTES - ", TimeToString(TimeCurrent()));
   FileWrite(handle, "=========================================");
   FileWrite(handle, "");
   FileWrite(handle, "Condition 1: Bougie journaliere EN COURS = HAUSSIERE");
   FileWrite(handle, "Condition 2: Bas actuel < Bas de la bougie precedente");
   FileWrite(handle, "");
   FileWrite(handle, "-----------------------------------------");
   
   if(nbDetections == 0)
   {
      FileWrite(handle, "Aucun actif detecte pour le moment");
   }
   else
   {
      FileWrite(handle, "Nombre d'actifs: ", nbDetections);
      FileWrite(handle, "");
      
      for(int i = 0; i < nbDetections; i++)
      {
         FileWrite(handle, IntegerToString(i+1) + ". " + symbolesDetectes[i]);
      }
   }
   
   FileWrite(handle, "=========================================");
   FileClose(handle);
   
   if(nbDetections > 0)
      Print("📁 Fichier mis a jour: ", FichierSortie, " (", nbDetections, " actifs)");
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("🛑 Scanner arreté - Dernier scan effectué");
}
//+------------------------------------------------------------------+
