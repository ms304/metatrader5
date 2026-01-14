//+------------------------------------------------------------------+
//|                                                MarketScanner.mq5 |
//|                                  Script de scan de volatilité    |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Généré par IA"
#property link      ""
#property version   "1.00"
#property script_show_inputs

//--- Paramètres d'entrée
input int InpMaxResults = 20; // Nombre d'actifs à afficher dans la liste

//--- Structure pour stocker les données d'un actif
struct AssetData
  {
   string            symbol;
   double            percentChange;
   double            absChange; // Utilisé pour le tri (valeur absolue)
  };

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
   // Récupération de l'unité de temps du graphique actuel
   ENUM_TIMEFRAMES currentPeriod = Period();
   string periodString = EnumToString(currentPeriod);
   
   Print("--- Démarrage du scan sur l'unité de temps : ", periodString, " ---");

   // Tableau pour stocker les résultats
   AssetData results[];
   
   // Récupérer le nombre total de symboles dans le Market Watch
   int totalSymbols = SymbolsTotal(true); // true = seulement le Market Watch
   
   // Redimensionner le tableau au pire des cas (tous les symboles)
   ArrayResize(results, totalSymbols);
   
   int count = 0;

   // Boucle sur tous les symboles du Market Watch
   for(int i = 0; i < totalSymbols; i++)
     {
      string symbol = SymbolName(i, true);
      
      // Récupération du prix d'ouverture de la bougie actuelle (index 0)
      // On utilise iOpen pour avoir l'ouverture de la barre en cours de formation
      double openPrice = iOpen(symbol, currentPeriod, 0);
      
      // Récupération du prix actuel (Bid)
      double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
      
      // Vérification basique pour éviter les divisions par zéro ou erreurs de données
      if(openPrice == 0 || currentPrice == 0)
         continue;

      // Calcul de la variation en pourcentage
      double change = ((currentPrice - openPrice) / openPrice) * 100.0;
      
      // Stockage dans la structure
      results[count].symbol = symbol;
      results[count].percentChange = change;
      results[count].absChange = MathAbs(change); // On stocke la valeur absolue pour le tri
      
      count++;
     }

   // Redimensionner le tableau à la taille réelle des données récupérées
   ArrayResize(results, count);

   // Tri du tableau (Tri à bulles simple pour classer par plus gros mouvement absolu)
   // Nous voulons voir ceux qui ont le plus bougé (hausse ou baisse) en premier
   for(int i = 0; i < count - 1; i++)
     {
      for(int j = 0; j < count - i - 1; j++)
        {
         if(results[j].absChange < results[j + 1].absChange)
           {
            // Échange
            AssetData temp = results[j];
            results[j] = results[j + 1];
            results[j + 1] = temp;
           }
        }
     }

   // Affichage des résultats
   Print("-------------------------------------------------------------");
   Print("TOP ", InpMaxResults, " des mouvements sur la bougie en cours (", periodString, ") :");
   Print("Symbole | Variation % | Prix Open -> Actuel");
   
   int limit = MathMin(InpMaxResults, count);
   
   for(int i = 0; i < limit; i++)
     {
      string dir = (results[i].percentChange >= 0) ? "[+]" : "[-]";
      
      PrintFormat("%d. %s %s %.2f%%", 
                  i + 1, 
                  results[i].symbol, 
                  dir,
                  results[i].percentChange);
     }
     
   Print("--- Fin du scan ---");
  }
//+------------------------------------------------------------------+
