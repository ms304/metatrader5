//+------------------------------------------------------------------+
//|                                    ICT_Last_FVG_Only_EA.mq5      |
//|                        Version Optimisée Temps Réel              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, mc0d3"
#property link      "https://www.mql5.com"
#property version   "1.01"
#property strict

#include <Trade\Trade.mqh>

//--- Paramètres d'entrée
input group "=== Paramètres FVG ==="
input bool     ExtendBoxes  = true;     // Étendre la boîte vers la droite (temps réel)
input int      BoxWidthBars = 20;       // Largeur si non étendue (en barres)

input group "=== Couleurs ==="
input color    BullishColor = clrLimeGreen; 
input color    BearishColor = clrRed;

input group "=== Paramètres de Trading ==="
input bool     AutoTrade    = false;    
input double   LotSize      = 0.1;      
input int      MagicNumber  = 654321;   
input double   StopLossPts  = 500;      
input double   TakeProfitPts = 1000;    

//--- Variables globales
CTrade trade;
string Prefix = "LastFVG_";
string objName = "LastFVG_Active";

//+------------------------------------------------------------------+
//| Initialisation                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    ObjectsDeleteAll(0, Prefix);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Désinitialisation                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, Prefix);
}

//+------------------------------------------------------------------+
//| Boucle principale Tick                                            |
//+------------------------------------------------------------------+
void OnTick()
{
    // --- 1. Récupération des données ---
    MqlRates rates[];
    ArraySetAsSeries(rates, true); 
    int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, 100, rates);
    if(copied <= 4) return;

    bool foundFVG = false;
    bool isBullish = false;
    double zoneHigh = 0, zoneLow = 0;
    datetime timeStart = 0;

    // --- 2. Recherche du FVG le plus récent (en partant de la bougie 1) ---
    // Un FVG se détecte entre la bougie i+2 et la bougie i
    for(int i = 1; i < copied - 2; i++)
    {
        // FVG HAUSSIER (Trou entre le High de i+1 et le Low de i-1 / ou ici rates[i] et rates[i+2])
        if(rates[i].low > rates[i+2].high)
        {
            foundFVG = true;
            isBullish = true;
            zoneHigh = rates[i].low;
            zoneLow  = rates[i+2].high;
            timeStart = rates[i+2].time;
            break; // On a trouvé le plus récent, on sort
        }
        
        // FVG BAISSIER
        if(rates[i].high < rates[i+2].low)
        {
            foundFVG = true;
            isBullish = false;
            zoneHigh = rates[i+2].low;
            zoneLow  = rates[i].high;
            timeStart = rates[i+2].time;
            break; // On a trouvé le plus récent, on sort
        }
    }

    // --- 3. Gestion Graphique ---
    if(foundFVG)
    {
        // Calcul du temps de fin (dynamique si ExtendBoxes est vrai)
        datetime timeEnd = (ExtendBoxes) ? rates[0].time + PeriodSeconds() * 2 : timeStart + PeriodSeconds() * BoxWidthBars;
        
        DrawRect(objName, timeStart, zoneHigh, timeEnd, zoneLow, isBullish ? BullishColor : BearishColor);
        
        // --- 4. Gestion du Trading (Optionnel) ---
        if(AutoTrade && CheckNewBar()) 
        {
            DeletePendingOrders();
            double entryPrice = (zoneHigh + zoneLow) / 2;
            
            if(isBullish)
            {
                double sl = zoneLow - (StopLossPts * _Point);
                double tp = zoneHigh + (TakeProfitPts * _Point);
                trade.BuyLimit(LotSize, entryPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "FVG Buy");
            }
            else
            {
                double sl = zoneHigh + (StopLossPts * _Point);
                double tp = zoneLow - (TakeProfitPts * _Point);
                trade.SellLimit(LotSize, entryPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "FVG Sell");
            }
        }
    }
    else
    {
        if(ObjectFind(0, objName) >= 0) ObjectDelete(0, objName);
    }
}

//+------------------------------------------------------------------+
//| Fonction pour dessiner/mettre à jour le rectangle                |
//+------------------------------------------------------------------+
void DrawRect(string name, datetime t1, double p1, datetime t2, double p2, color clr)
{
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    }
    
    // Mise à jour en temps réel
    ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
    ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Détection de nouvelle bougie (pour le trading uniquement)        |
//+------------------------------------------------------------------+
bool CheckNewBar()
{
    static datetime lastBar;
    datetime currBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(lastBar != currBar)
    {
        lastBar = currBar;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Supprimer les ordres en attente                                  |
//+------------------------------------------------------------------+
void DeletePendingOrders()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == MagicNumber)
                trade.OrderDelete(ticket);
        }
    }
}
