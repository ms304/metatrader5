#property indicator_chart_window
#property indicator_plots 0

//--- INPUTS
input group "Paramètres Session"
input int      StartHour      = 0;
input int      EndHour        = 8;
input color    ColorBox       = C'40,65,65';
input color    ColorHighLow   = clrMediumAquamarine;

input group "Extensions Fibonacci"
input color    ColorFibo      = clrGray; 
input bool     ShowFibo       = true;    
input int      FiboExtendHours = 10;     // Prolongation des lignes Fib en heures

//--- GLOBALS
string g_prefix = "Asian_";

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
{
   // On utilise l'heure du dernier bar connu
   datetime lastBarTime = iTime(_Symbol, _Period, 0);
   MqlDateTime dt; 
   TimeToStruct(lastBarTime, dt);
   
   // Construction des dates de début et de fin
   dt.hour = StartHour; dt.min = 0; dt.sec = 0;
   datetime sTime = StructToTime(dt);
   
   dt.hour = EndHour;
   datetime eTime = StructToTime(dt);

   // Utilisation de GetBarShift au lieu de iBarShift
   int startBar = GetBarShift(_Symbol, _Period, sTime);
   int endBar   = GetBarShift(_Symbol, _Period, eTime);

   int count = startBar - endBar;
   
   if(count > 0) {
      double h = HighValue(_Symbol, _Period, count, endBar);
      double l = LowValue(_Symbol, _Period, count, endBar);
      
      double mid = (h + l) / 2.0;
      double dist = h - mid; 

      // 1. Dessin des lignes principales
      DrawBox(g_prefix+"RECT", sTime, eTime, h, l);
      DrawLine(g_prefix+"HIGH", sTime, eTime + (6*3600), h, ColorHighLow, 2, STYLE_SOLID, "Asian High : " + DoubleToString(h, _Digits));
      DrawLine(g_prefix+"LOW", sTime, eTime + (6*3600), l, ColorHighLow, 2, STYLE_SOLID, "Asian Low : " + DoubleToString(l, _Digits));
      DrawLine(g_prefix+"MID", sTime, eTime, mid, clrOrange, 1, STYLE_DOT, "Equilibrium : " + DoubleToString(mid, _Digits));

      if(ShowFibo) {
         datetime fibEndTime = eTime + (FiboExtendHours * 3600);
         
         // Extensions vers le HAUT (Intégration du niveau ET du prix dans la description)
         DrawLine(g_prefix+"FIB_H_0.618", eTime, fibEndTime, mid + (dist * 0.618), ColorFibo, 1, STYLE_DASH, "+0.618 Fib : " + DoubleToString(mid + (dist * 0.618), _Digits));
         DrawLine(g_prefix+"FIB_H_1.272", eTime, fibEndTime, mid + (dist * 1.272), ColorFibo, 1, STYLE_DASH, "+1.272 Fib : " + DoubleToString(mid + (dist * 1.272), _Digits));
         DrawLine(g_prefix+"FIB_H_1.618", eTime, fibEndTime, mid + (dist * 1.618), ColorFibo, 1, STYLE_DASH, "+1.618 Fib : " + DoubleToString(mid + (dist * 1.618), _Digits));
         DrawLine(g_prefix+"FIB_H_2.000", eTime, fibEndTime, mid + (dist * 2.000), ColorFibo, 1, STYLE_DASH, "+2.000 Fib : " + DoubleToString(mid + (dist * 2.000), _Digits));
         DrawLine(g_prefix+"FIB_H_2.618", eTime, fibEndTime, mid + (dist * 2.618), ColorFibo, 1, STYLE_DASH, "+2.618 Fib : " + DoubleToString(mid + (dist * 2.618), _Digits));
         DrawLine(g_prefix+"FIB_H_3.618", eTime, fibEndTime, mid + (dist * 3.618), ColorFibo, 1, STYLE_DASH, "+3.618 Fib : " + DoubleToString(mid + (dist * 3.618), _Digits));
         DrawLine(g_prefix+"FIB_H_4.236", eTime, fibEndTime, mid + (dist * 4.236), ColorFibo, 1, STYLE_DASH, "+4.236 Fib : " + DoubleToString(mid + (dist * 4.236), _Digits));
         DrawLine(g_prefix+"FIB_H_5.000", eTime, fibEndTime, mid + (dist * 5.000), ColorFibo, 1, STYLE_DASH, "+5.000 Fib : " + DoubleToString(mid + (dist * 5.000), _Digits));
         
         // Extensions vers le BAS (Intégration du niveau ET du prix dans la description)
         DrawLine(g_prefix+"FIB_L_0.618", eTime, fibEndTime, mid - (dist * 0.618), ColorFibo, 1, STYLE_DASH, "-0.618 Fib : " + DoubleToString(mid - (dist * 0.618), _Digits));
         DrawLine(g_prefix+"FIB_L_1.272", eTime, fibEndTime, mid - (dist * 1.272), ColorFibo, 1, STYLE_DASH, "-1.272 Fib : " + DoubleToString(mid - (dist * 1.272), _Digits));
         DrawLine(g_prefix+"FIB_L_1.618", eTime, fibEndTime, mid - (dist * 1.618), ColorFibo, 1, STYLE_DASH, "-1.618 Fib : " + DoubleToString(mid - (dist * 1.618), _Digits));
         DrawLine(g_prefix+"FIB_L_2.000", eTime, fibEndTime, mid - (dist * 2.000), ColorFibo, 1, STYLE_DASH, "-2.000 Fib : " + DoubleToString(mid - (dist * 2.000), _Digits));
         DrawLine(g_prefix+"FIB_L_2.618", eTime, fibEndTime, mid - (dist * 2.618), ColorFibo, 1, STYLE_DASH, "-2.618 Fib : " + DoubleToString(mid - (dist * 2.618), _Digits));
         DrawLine(g_prefix+"FIB_L_3.618", eTime, fibEndTime, mid - (dist * 3.618), ColorFibo, 1, STYLE_DASH, "-3.618 Fib : " + DoubleToString(mid - (dist * 3.618), _Digits));
         DrawLine(g_prefix+"FIB_L_4.236", eTime, fibEndTime, mid - (dist * 4.236), ColorFibo, 1, STYLE_DASH, "-4.236 Fib : " + DoubleToString(mid - (dist * 4.236), _Digits));
         DrawLine(g_prefix+"FIB_L_5.000", eTime, fibEndTime, mid - (dist * 5.000), ColorFibo, 1, STYLE_DASH, "-5.000 Fib : " + DoubleToString(mid - (dist * 5.000), _Digits));
      }
   }
   return(rates_total);
}

//--- FONCTION RENOMMÉE POUR ÉVITER LE CONFLIT (GetBarShift au lieu de iBarShift)
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
   
   // Affiche la description dans la liste des objets et sur le graphique (si "Montrer description" est coché)
   ObjectSetString(0, name, OBJPROP_TEXT, desc);
   
   // Affiche l'infobulle au survol de la souris avec le texte dynamique (niveau + prix)
   ObjectSetString(0, name, OBJPROP_TOOLTIP, desc);
}
