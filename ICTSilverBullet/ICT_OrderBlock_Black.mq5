//+------------------------------------------------------------------+
//|                                         ICT_OrderBlock_Black.mq5 |
//|                                  Copyright 2026, Trading AI/ICT  |
//|                       Version : Carrés Noirs Non Remplis         |
//+------------------------------------------------------------------+
#property copyright "ICT Trader T0W3RBU5T3R"
#property link      "https://www.mql5.com"
#property version   "1.01"
#property strict

//--- Paramètres d'entrée
input int      InpLookback = 150;       // Nombre de bougies à analyser
input int      InpWidth    = 2;         // Épaisseur du trait
input bool     InpShowMT    = true;     // Afficher le Mean Threshold (50%)

//--- Variables Globales
datetime last_process = 0;

int OnInit() { return(INIT_SUCCEEDED); }

void OnDeinit(const int reason) { ObjectsDeleteAll(0, "ICT_EA_"); }

void OnTick()
{
    datetime currentTime = iTime(_Symbol, _Period, 0);
    if(currentTime != last_process)
    {
        ScanOrderBlocks();
        last_process = currentTime;
    }
    CheckInvalidation();
}

void ScanOrderBlocks()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, _Period, 0, InpLookback + 5, rates) < 0) return;

    for(int i = 2; i < InpLookback; i++)
    {
        // 1. BULLISH OB (Achat)
        if(rates[i].close < rates[i].open) 
        {
            if(rates[i-1].close > rates[i].high && rates[i-2].low > rates[i].high)
            {
                string name = "ICT_EA_BullOB_" + TimeToString(rates[i].time);
                double mt = (rates[i].open + rates[i].close) / 2.0;
                CreateOB(name, rates[i].time, rates[i].high, rates[i].low, mt);
            }
        }
        // 2. BEARISH OB (Vente)
        if(rates[i].close > rates[i].open) 
        {
            if(rates[i-1].close < rates[i].low && rates[i-2].high < rates[i].low)
            {
                string name = "ICT_EA_BearOB_" + TimeToString(rates[i].time);
                double mt = (rates[i].open + rates[i].close) / 2.0;
                CreateOB(name, rates[i].time, rates[i].high, rates[i].low, mt);
            }
        }
    }
}

void CreateOB(string name, datetime t, double h, double l, double mt)
{
    if(ObjectFind(0, name) < 0)
    {
        // Création du rectangle NOIR et VIDE
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, t, h, t + PeriodSeconds()*10, l);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);    // COULEUR NOIRE
        ObjectSetInteger(0, name, OBJPROP_FILL, false);       // NON REMPLI
        ObjectSetInteger(0, name, OBJPROP_WIDTH, InpWidth);    // ÉPAISSEUR
        ObjectSetInteger(0, name, OBJPROP_BACK, false);       // DEVANT LE PRIX
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

        if(InpShowMT)
        {
            string mt_name = name + "_MT";
            ObjectCreate(0, mt_name, OBJ_TREND, 0, t, mt, t + PeriodSeconds()*10, mt);
            ObjectSetInteger(0, mt_name, OBJPROP_COLOR, clrBlack); // MT EN NOIR AUSSI
            ObjectSetInteger(0, mt_name, OBJPROP_STYLE, STYLE_DOT);
        }
    }
}

void CheckInvalidation()
{
    double lastClose = iClose(_Symbol, _Period, 0);
    datetime lastTime = iTime(_Symbol, _Period, 0);
    int total = ObjectsTotal(0, 0, -1);
    
    for(int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, 0);
        if(StringFind(name, "ICT_EA_") == 0 && StringFind(name, "_MT") < 0)
        {
            // Extension vers la droite
            ObjectSetInteger(0, name, OBJPROP_TIME, 1, lastTime + PeriodSeconds()*5);
            
            string mt_name = name + "_MT";
            if(ObjectFind(0, mt_name) >= 0)
            {
                ObjectSetInteger(0, mt_name, OBJPROP_TIME, 1, lastTime + PeriodSeconds()*5);
                double mt_price = ObjectGetDouble(0, mt_name, OBJPROP_PRICE, 0);
                
                // Invalidation : Si le prix clôture au-delà du Mean Threshold, on met en pointillés fins
                bool isBull = (StringFind(name, "BullOB") >= 0);
                if((isBull && lastClose < mt_price) || (!isBull && lastClose > mt_price))
                {
                    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
                    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
                }
            }
        }
    }
}
