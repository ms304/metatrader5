//+------------------------------------------------------------------+
//|                                              LastSweepFinder.mq5 |
//|                                  Copyright 2026, Trading AI Corp |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "1.02"
#property strict

//--- Paramètres d'entrée
input int      InpLookback = 300;      // Nombre de bougies à analyser
input int      InpSwingStrength = 5;   // Nombre de bougies de part et d'autre d'un sommet
input color    InpColorHigh = clrRed;  // Couleur Sweep High
input color    InpColorLow = clrAqua;  // Couleur Sweep Low
input int      InpLineWidth = 2;       // Épaisseur des lignes

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, "LastSweepHigh");
   ObjectDelete(0, "LastSweepLow");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateSweeps();
}

//+------------------------------------------------------------------+
//| Fonction principale de détection                                |
//+------------------------------------------------------------------+
void UpdateSweeps()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // On prend une marge de sécurité pour le calcul des swings
   int barsNeeded = InpLookback + (InpSwingStrength * 2) + 1;
   int copied = CopyRates(_Symbol, _Period, 0, barsNeeded, rates);
   
   // Si l'historique n'est pas encore chargé, on quitte proprement
   if(copied < barsNeeded) return;

   double lastSweepHighPrice = 0;
   double lastSweepLowPrice = 0;

   // 1. CHERCHER LE DERNIER SWEEP HIGH
   // On commence à i = InpSwingStrength pour pouvoir vérifier les bougies à sa gauche
   for(int i = 1; i < copied - (InpSwingStrength * 2); i++)
   {
      // 'prev' est le sommet historique que l'on va potentiellement "sweeper"
      for(int prev = i + 1; prev < copied - InpSwingStrength; prev++)
      {
         if(IsSwingHigh(rates, prev, InpSwingStrength, copied))
         {
            double swingLevel = rates[prev].high;
            
            // Condition de Sweep : 
            // La mèche de la bougie 'i' dépasse le sommet 'prev', mais la clôture de 'i' est dessous.
            if(rates[i].high > swingLevel && rates[i].close < swingLevel)
            {
               lastSweepHighPrice = rates[i].high;
               break; 
            }
         }
      }
      if(lastSweepHighPrice > 0) break;
   }

   // 2. CHERCHER LE DERNIER SWEEP LOW
   for(int i = 1; i < copied - (InpSwingStrength * 2); i++)
   {
      for(int prev = i + 1; prev < copied - InpSwingStrength; prev++)
      {
         if(IsSwingLow(rates, prev, InpSwingStrength, copied))
         {
            double swingLevel = rates[prev].low;
            
            // Condition de Sweep :
            // La mèche de la bougie 'i' descend sous le creux 'prev', mais la clôture de 'i' est au-dessus.
            if(rates[i].low < swingLevel && rates[i].close > swingLevel)
            {
               lastSweepLowPrice = rates[i].low;
               break;
            }
         }
      }
      if(lastSweepLowPrice > 0) break;
   }

   // Dessin des lignes (mise à jour uniquement si un prix a été trouvé)
   if(lastSweepHighPrice > 0)
      DrawSweepLine("LastSweepHigh", lastSweepHighPrice, InpColorHigh, "Last Sweep High");
   
   if(lastSweepLowPrice > 0)
      DrawSweepLine("LastSweepLow", lastSweepLowPrice, InpColorLow, "Last Sweep Low");
      
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Vérifie si une bougie est un sommet local (Sécurité renforcée)   |
//+------------------------------------------------------------------+
bool IsSwingHigh(const MqlRates &rates[], int index, int strength, int total)
{
   // Vérification stricte des limites du tableau
   if(index - strength < 0 || index + strength >= total) return false;

   for(int j = 1; j <= strength; j++)
   {
      if(rates[index].high <= rates[index-j].high || rates[index].high <= rates[index+j].high)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Vérifie si une bougie est un creux local (Sécurité renforcée)    |
//+------------------------------------------------------------------+
bool IsSwingLow(const MqlRates &rates[], int index, int strength, int total)
{
   // Vérification stricte des limites du tableau
   if(index - strength < 0 || index + strength >= total) return false;

   for(int j = 1; j <= strength; j++)
   {
      if(rates[index].low >= rates[index-j].low || rates[index].low >= rates[index+j].low)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Dessiner une ligne horizontale                                   |
//+------------------------------------------------------------------+
void DrawSweepLine(string name, double price, color clr, string text)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, InpLineWidth);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false); // Affiche la ligne au premier plan
   }
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   }
}
