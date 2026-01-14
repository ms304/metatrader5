#property indicator_chart_window
#property indicator_plots 0

//--- PARAMÈTRES
input int      StartHour      = 0;
input int      EndHour        = 8;
input color    ColorBorder    = clrGray;         // Couleur du contour du rectangle
input color    ColorHighLow   = clrMediumAquamarine; // Couleur des lignes de Liquidité
input color    ColorFibo      = clrGray;         // Couleur des extensions Fibonacci
input bool     ShowFibo       = true;

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
{
   MqlDateTime dt; 
   TimeCurrent(dt);
   
   string datePrefix = IntegerToString(dt.year)+"."+IntegerToString(dt.mon)+"."+IntegerToString(dt.day);
   datetime sTime = StringToTime(datePrefix + " " + (StartHour < 10 ? "0" : "") + IntegerToString(StartHour) + ":00");
   datetime eTime = StringToTime(datePrefix + " " + (EndHour < 10 ? "0" : "") + IntegerToString(EndHour) + ":00");

   int startBar = iBarShift(_Symbol, _Period, sTime, false);
   int endBar   = iBarShift(_Symbol, _Period, eTime, false);
   
   if(iTime(_Symbol, _Period, startBar) < sTime) startBar--;

   int count = startBar - endBar;
   
   if(count > 0) 
   {
      double h = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, count, endBar + 1));
      double l = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, count, endBar + 1));
      double mid = (h + l) / 2.0;
      double dist = h - mid; // Distance Mid -> High

      // 1. DESSIN DU CADRE (RECTANGLE SANS REMPLISSAGE)
      DrawBox("AS_RECT", sTime, eTime, h, l, ColorBorder);

      // 2. DESSIN DES LIGNES PRINCIPALES
      DrawLine("AS_HIGH", sTime, eTime + (8*3600), h, ColorHighLow, 2, STYLE_SOLID);
      DrawLine("AS_LOW", sTime, eTime + (8*3600), l, ColorHighLow, 2, STYLE_SOLID);
      DrawLine("AS_MID", sTime, eTime, mid, clrOrange, 1, STYLE_DOT);

      // 3. DESSIN DES EXTENSIONS FIBONACCI (1.618, 2.618, 3.618, 4.236)
      if(ShowFibo) 
      {
         datetime fibEnd = eTime + (12 * 3600); 
         
         // Extensions Hautes
         DrawLine("FIB_H1", eTime, fibEnd, mid + (dist * 1.618), ColorFibo, 1, STYLE_DASH);
         DrawLine("FIB_H2", eTime, fibEnd, mid + (dist * 2.618), ColorFibo, 1, STYLE_DASH);
         DrawLine("FIB_H3", eTime, fibEnd, mid + (dist * 3.618), ColorFibo, 1, STYLE_DASH);
         DrawLine("FIB_H4", eTime, fibEnd, mid + (dist * 4.236), ColorFibo, 1, STYLE_DASH); // <-- Nouveau

         // Extensions Basses
         DrawLine("FIB_L1", eTime, fibEnd, mid - (dist * 1.618), ColorFibo, 1, STYLE_DASH);
         DrawLine("FIB_L2", eTime, fibEnd, mid - (dist * 2.618), ColorFibo, 1, STYLE_DASH);
         DrawLine("FIB_L3", eTime, fibEnd, mid - (dist * 3.618), ColorFibo, 1, STYLE_DASH);
         DrawLine("FIB_L4", eTime, fibEnd, mid - (dist * 4.236), ColorFibo, 1, STYLE_DASH); // <-- Nouveau
      }
   }
   return(rates_total);
}

//+------------------------------------------------------------------+
//| FONCTION DESSIN RECTANGLE                                        |
//+------------------------------------------------------------------+
void DrawBox(string name, datetime t1, datetime t2, double p1, double p2, color col)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);     // Couleur de la bordure
   ObjectSetInteger(0, name, OBJPROP_FILL, false);    // <--- METTRE SUR FALSE ICI
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT); // Bordure en pointillés
   ObjectSetInteger(0, name, OBJPROP_BACK, true);     // Derrière les bougies
}

//+------------------------------------------------------------------+
//| FONCTION DESSIN LIGNE                                            |
//+------------------------------------------------------------------+
void DrawLine(string name, datetime t1, datetime t2, double p, color col, int width, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, t1, p, t2, p);
   
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
}

void OnDeinit(const int reason) { ObjectsDeleteAll(0, "AS_"); ObjectsDeleteAll(0, "FIB_"); }
