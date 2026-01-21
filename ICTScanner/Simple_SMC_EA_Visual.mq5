//+------------------------------------------------------------------+
//|                                          Simple_SMC_EA_Visual.mq5|
//|                        Based on logic from LuxAlgo SMC Concept   |
//+------------------------------------------------------------------+
#property copyright "Adaptation SMC Visuelle"
#property version   "1.02"
#include <Trade\Trade.mqh>

//--- INPUTS
input int      SwingLength = 10;       // Longueur pour définir un Swing (ex: 10 bougies)
input int      MagicNumber = 123456;   // Identifiant unique du robot

//--- VARIABLES GLOBALES
CTrade trade;
int trendBias = 0; // 1 = Haussier (Bullish), -1 = Baissier (Bearish)
double lastSwingHigh = 0;
double lastSwingLow = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Création des lignes graphiques au démarrage
   ObjectCreate(0, "SMC_High_Line", OBJ_HLINE, 0, 0, 0);
   ObjectSetInteger(0, "SMC_High_Line", OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, "SMC_High_Line", OBJPROP_WIDTH, 2);
   
   ObjectCreate(0, "SMC_Low_Line", OBJ_HLINE, 0, 0, 0);
   ObjectSetInteger(0, "SMC_Low_Line", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "SMC_Low_Line", OBJPROP_WIDTH, 2);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Nettoyage : On supprime les lignes et le texte quand on enlève l'EA
   ObjectDelete(0, "SMC_High_Line");
   ObjectDelete(0, "SMC_Low_Line");
   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Récupération des données
   double prevClose = iClose(_Symbol, _Period, 1);
   
   // Si pas assez de données, on attend
   if(prevClose == 0) return; 

   // 1. DÉTECTION DES SWINGS (Plus Haut / Plus Bas sur X périodes)
   int highIndex = iHighest(_Symbol, _Period, MODE_HIGH, SwingLength, 1);
   int lowIndex  = iLowest(_Symbol, _Period, MODE_LOW, SwingLength, 1);

   double currentHigh = iHigh(_Symbol, _Period, highIndex);
   double currentLow  = iLow(_Symbol, _Period, lowIndex);

   // Initialisation au premier lancement
   if(lastSwingHigh == 0) lastSwingHigh = currentHigh;
   if(lastSwingLow == 0) lastSwingLow = currentLow;

   // 2. LOGIQUE DE CASSURE (BOS)
   string signalMsg = "En attente...";
   
   // BOS HAUSSIER
   if (prevClose > lastSwingHigh)
     {
      trendBias = 1; // Structure Haussière
      lastSwingHigh = currentHigh; // Le haut est cassé, on cherche le prochain sommet
      signalMsg = "BOS HAUSSIER DETECTÉ !";
     }
     // Si on ne casse pas, mais qu'un nouveau sommet plus bas se forme, on met à jour le trailing high
     else if (currentHigh < lastSwingHigh && highIndex < SwingLength/2) 
     {
        // Logique simplifiée pour suivre le prix
        // lastSwingHigh = currentHigh; 
     }

   // BOS BAISSIER
   if (prevClose < lastSwingLow)
     {
      trendBias = -1; // Structure Baissière
      lastSwingLow = currentLow; // Le bas est cassé
      signalMsg = "BOS BAISSIER DETECTÉ !";
     }

   // Mise à jour constante des Swings actuels si on fait des nouveaux plus hauts/bas sans casser la structure inverse
   if(trendBias == 1 && currentHigh > lastSwingHigh) lastSwingHigh = currentHigh;
   if(trendBias == -1 && currentLow < lastSwingLow) lastSwingLow = currentLow;


   // 3. AFFICHAGE VISUEL (Ce qui manquait)
   
   // A. Mise à jour des lignes sur le graphique
   ObjectMove(0, "SMC_High_Line", 0, 0, lastSwingHigh);
   ObjectMove(0, "SMC_Low_Line", 0, 0, lastSwingLow);
   
   // B. Affichage du texte en haut à gauche
   string trendText = (trendBias == 1) ? "HAUSSIER (Bullish)" : (trendBias == -1) ? "BAISSIER (Bearish)" : "NEUTRE";
   
   Comment("\n",
           "=== SMART MONEY CONCEPT EA ===", "\n",
           "Symbole : ", _Symbol, "\n",
           "Tendance Structure : ", trendText, "\n",
           "-----------------------------", "\n",
           "Swing High (Ligne Verte) : ", lastSwingHigh, "\n",
           "Swing Low  (Ligne Rouge) : ", lastSwingLow, "\n",
           "Prix Actuel : ", iClose(_Symbol, _Period, 0), "\n",
           "Dernier Signal : ", signalMsg
           );
           
   ChartRedraw(0); // Force le rafraichissement du graphique
  }
