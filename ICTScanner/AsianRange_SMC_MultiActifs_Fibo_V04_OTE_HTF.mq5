#property indicator_chart_window
#property indicator_plots 0

//--- INPUTS
input group "Paramètres Session"
input int      StartHour      = 0;
input int      EndHour        = 8;
input color    ColorBox       = C'40,65,65';
input color    ColorHighLow   = clrMediumAquamarine;

input group "Niveaux HTF (Daily/Weekly)"
input bool     ShowHTF        = true;
input color    ColorPDH_PDL   = clrRed;
input color    ColorPWH_PWL   = clrGold;

input group "Fibo Internes (OTE - Expérimental)"
input bool     ShowFiboInt    = true;
input color    ColorFiboInt   = clrMediumPurple;

input group "Extensions Fibonacci (Externes)"
input bool     ShowFiboExt    = true;
input color    ColorFiboExt   = clrGray; 

//--- GLOBALS
string g_prefix = "Asian_Full_";

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
{
   datetime lastBarTime = iTime(_Symbol, _Period, 0);
   MqlDateTime dt; 
   TimeToStruct(lastBarTime, dt);
   
   // Calcul de la fin de journée (Midnight)
   dt.hour = 23; dt.min = 59; dt.sec = 59;
   datetime midnightTime = StructToTime(dt);
   
   // Définition de la session
   dt.hour = StartHour; dt.min = 0; dt.sec = 0;
   datetime sTime = StructToTime(dt);
   dt.hour = EndHour;
   datetime eTime = StructToTime(dt);

   int startBar = GetBarShift(_Symbol, _Period, sTime);
   int endBar   = GetBarShift(_Symbol, _Period, eTime);
   int count = startBar - endBar;
   
   if(count > 0) {
      double h = HighValue(_Symbol, _Period, count, endBar);
      double l = LowValue(_Symbol, _Period, count, endBar);
      double mid = (h + l) / 2.0;
      double dist = h - mid; 

      // 1. Dessin de la Box Session
      DrawBox(g_prefix+"RECT", sTime, eTime, h, l);
      
      // 2. Lignes de base prolongées
      DrawLine(g_prefix+"HIGH", sTime, midnightTime, h, ColorHighLow, 2, STYLE_SOLID, "AH");
      DrawLine(g_prefix+"LOW", sTime, midnightTime, l, ColorHighLow, 2, STYLE_SOLID, "AL");
      DrawLine(g_prefix+"MID", sTime, midnightTime, mid, clrOrange, 1, STYLE_DOT, "AM (Equilibrium)");

      // 3. Niveaux HTF (Daily / Weekly)
      if(ShowHTF) {
         double pdh = iHigh(_Symbol, PERIOD_D1, 1);
         double pdl = iLow(_Symbol, PERIOD_D1, 1);
         double pwh = iHigh(_Symbol, PERIOD_W1, 1);
         double pwl = iLow(_Symbol, PERIOD_W1, 1);
         DrawLine(g_prefix+"PDH", sTime, midnightTime, pdh, ColorPDH_PDL, 1, STYLE_DASH, "PDH");
         DrawLine(g_prefix+"PDL", sTime, midnightTime, pdl, ColorPDH_PDL, 1, STYLE_DASH, "PDL");
         DrawLine(g_prefix+"PWH", sTime, midnightTime, pwh, ColorPWH_PWL, 1, STYLE_DASH, "PWH");
         DrawLine(g_prefix+"PWL", sTime, midnightTime, pwl, ColorPWH_PWL, 1, STYLE_DASH, "PWL");
      }

      // 4. FIBO INTERNES (OTE) prolongés
      if(ShowFiboInt) {
         double intLev[] = {0.618, 0.705, 0.786};
         for(int j=0; j<3; j++) {
            DrawLine(g_prefix+"OTE_H"+(string)j, sTime, midnightTime, mid+(dist*intLev[j]), ColorFiboInt, 1, STYLE_DOT, "");
            DrawLine(g_prefix+"OTE_L"+(string)j, sTime, midnightTime, mid-(dist*intLev[j]), ColorFiboInt, 1, STYLE_DOT, "");
         }
      }

      // 5. EXTENSIONS EXTERNES prolongées
      if(ShowFiboExt) {
         double extLev[] = {0.618, 1.272, 1.618, 2.0, 2.618, 3.618, 4.236, 5.0};
         for(int k=0; k<ArraySize(extLev); k++) {
            DrawLine(g_prefix+"EXT_H"+(string)k, eTime, midnightTime, mid+(dist*extLev[k]), ColorFiboExt, 1, STYLE_DASH, "");
            DrawLine(g_prefix+"EXT_L"+(string)k, eTime, midnightTime, mid-(dist*extLev[k]), ColorFiboExt, 1, STYLE_DASH, "");
         }
      }
   }
   return(rates_total);
}

//--- FONCTIONS UTILITAIRES
int GetBarShift(string symbol, ENUM_TIMEFRAMES period, datetime time) {
   datetime times[];
   if(CopyTime(symbol, period, time, 1, times) > 0) return Bars(symbol, period, times[0], iTime(symbol, period, 0)) - 1;
   return -1;
}

double HighValue(string sym, ENUM_TIMEFRAMES tf, int count, int start) {
   double val[];
   if(CopyHigh(sym, tf, start, count, val) > 0) return val[ArrayMaximum(val)];
   return 0;
}

double LowValue(string sym, ENUM_TIMEFRAMES tf, int count, int start) {
   double val[];
   if(CopyLow(sym, tf, start, count, val) > 0) return val[ArrayMinimum(val)];
   return 0;
}

void DrawBox(string name, datetime t1, datetime t2, double h, double l) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, h, t2, l);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_COLOR, ColorBox);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, h);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, l);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
}

void DrawLine(string name, datetime t1, datetime t2, double p, color c, int w, ENUM_LINE_STYLE s, string desc) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, t1, p, t2, p);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, name, OBJPROP_STYLE, s);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, name, OBJPROP_TEXT, desc);
}
