//+------------------------------------------------------------------+
//|                                         AsianRange_SMC_V3.mq5    |
//|                                  Copyright 2024, Trading Robot   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "3.00"
#property strict

//--- PARAMÈTRES D'AFFICHAGE
input int      StartHour      = 0;            // Début session (0 pour Minuit)
input int      EndHour        = 8;            // Fin session (8 pour 08:00)
input color    ColorHighLow   = clrMediumAquamarine; // Couleur zones de liquidité
input color    ColorBox       = C'40,65,65';   // Couleur du fond (Style TradingView)
input color    ColorMid       = clrOrange;     // Couleur Equilibrium
input int      WidthHighLow   = 1;            // Épaisseur des lignes de sweep

//--- VARIABLES GLOBALES
double asianHigh = 0;
double asianLow  = 0;

int OnInit() { return(INIT_SUCCEEDED); }
void OnDeinit(const int reason) { ObjectsDeleteAll(0, "ASIAN_"); }

void OnTick()
{
    MqlDateTime dt;
    TimeCurrent(dt);
    
    // On définit la date du jour actuel pour le calcul
    string datePrefix = IntegerToString(dt.year)+"."+IntegerToString(dt.mon)+"."+IntegerToString(dt.day);
    datetime startTime = StringToTime(datePrefix + " " + (StartHour < 10 ? "0" : "") + IntegerToString(StartHour) + ":00");
    datetime endTime   = StringToTime(datePrefix + " " + (EndHour < 10 ? "0" : "") + IntegerToString(EndHour) + ":00");

    // Trouver les indices des bougies de façon précise
    int startBar = iBarShift(_Symbol, _Period, startTime, false);
    int endBar   = iBarShift(_Symbol, _Period, endTime, false);
    
    // SÉCURITÉ : Si la bougie trouvée est AVANT l'heure de début (ex: 23h), on prend la suivante
    if(iTime(_Symbol, _Period, startBar) < startTime) startBar--;
    // Si la bougie de fin est après l'heure de fin, on recule
    if(iTime(_Symbol, _Period, endBar) > endTime) endBar++;

    int count = startBar - endBar; // Nombre de bougies dans la session

    if(count > 0)
    {
        // Calcul des niveaux
        asianHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, count, endBar + 1));
        asianLow  = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, count, endBar + 1));
        double asianMid = (asianHigh + asianLow) / 2;

        string id = IntegerToString(dt.day);

        // 1. LE RECTANGLE (FOND)
        DrawBox("ASIAN_RECT_"+id, startTime, endTime, asianHigh, asianLow);

        // 2. LES LIGNES DE LIQUIDITÉ (Étendu à droite pour voir le sweep)
        datetime extendTime = endTime + (6 * 3600); // Étendu de 6h après la fin
        
        DrawLine("ASIAN_HIGH_"+id, startTime, extendTime, asianHigh, ColorHighLow);
        DrawLine("ASIAN_LOW_"+id, startTime, extendTime, asianLow, ColorHighLow);
        DrawLine("ASIAN_MID_"+id, startTime, endTime, asianMid, ColorMid);
    }
}

void DrawBox(string name, datetime t1, datetime t2, double h, double l)
{
    if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, h, t2, l);
    ObjectSetInteger(0, name, OBJPROP_COLOR, ColorBox);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT); // Supprime le relief
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    // On met à jour les coordonnées pour que ça bouge en temps réel
    ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, h);
    ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 1, l);
}

void DrawLine(string name, datetime t1, datetime t2, double price, color col)
{
    if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
    ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
    ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, WidthHighLow);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, name, OBJPROP_STYLE, (name == "ASIAN_MID_" ? STYLE_DOT : STYLE_SOLID));
}
