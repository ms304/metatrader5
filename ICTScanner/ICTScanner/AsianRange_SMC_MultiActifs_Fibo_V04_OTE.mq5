#property indicator_chart_window
#property indicator_plots 0

//--- INPUTS
input group "Paramètres Session (Heures de PARIS)"
input int      StartHP        = 0;   
input int      EndHP          = 8;   
input int      OffsetFTMO     = 1;   
input color    ColorBox       = C'40,65,65';

input group "Extensions Fibonacci (Externes)"
input color    ColorFiboExt   = clrGray; 
input bool     ShowFiboExt    = true;    

input group "Fibo Internes (OTE - Expérimental)"
input color    ColorFiboInt   = clrMediumPurple; 
input bool     ShowFiboInt    = true;

//--- GLOBALS
string g_prefix = "TV_Exp_Extended_";

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
{
   if(rates_total < 500) return(rates_total);

   int brokerStart = (StartHP + OffsetFTMO) % 24;
   int brokerEnd   = (EndHP + OffsetFTMO) % 24;

   datetime now = TimeCurrent();
   MqlDateTime dt_now;
   TimeToStruct(now, dt_now);

   MqlDateTime st = dt_now, et = dt_now;
   st.hour = brokerStart; st.min = 0; st.sec = 0;
   et.hour = brokerEnd;   et.min = 0; et.sec = 0;

   datetime t_start = StructToTime(st);
   datetime t_end   = StructToTime(et);

   if(now < t_end) { t_start -= 86400; t_end -= 86400; }

   int idx_start = iBarShift(_Symbol, _Period, t_start);
   int idx_end   = iBarShift(_Symbol, _Period, t_end);

   double hSess = -1, lSess = 999999;
   for(int i = idx_start; i > idx_end; i--) {
      double valH = iHigh(_Symbol, _Period, i);
      double valL = iLow(_Symbol, _Period, i);
      if(valH > hSess) hSess = valH;
      if(valL < lSess) lSess = valL;
   }

   if(hSess != -1) {
      double mid = (hSess + lSess) / 2.0;
      double dist = hSess - mid; 

      MqlDateTime mdt = dt_now;
      mdt.hour = 23; mdt.min = 59; mdt.sec = 59;
      datetime midnight = StructToTime(mdt);

      // 1. Dessin de base (Rectangle de la session Asian)
      DrawBox(g_prefix+"RECT", t_start, t_end, hSess, lSess);
      
      // Lignes prolongées jusqu'à minuit
      DrawLine(g_prefix+"H", t_start, midnight, hSess, clrMediumAquamarine, 2, STYLE_SOLID, "AH");
      DrawLine(g_prefix+"L", t_start, midnight, lSess, clrMediumAquamarine, 2, STYLE_SOLID, "AL");
      DrawLine(g_prefix+"M", t_start, midnight, mid, clrOrange, 1, STYLE_DOT, "AM (Equilibrium)");

      // 2. Extensions Externes (Target Profit) prolongées
      if(ShowFiboExt) {
         double ext[] = {1.618, 2.618, 3.618, 4.618, 5.618};
         for(int k=0; k<ArraySize(ext); k++) {
            DrawLine(g_prefix+"UP_E"+(string)k, t_end, midnight, mid+(dist*ext[k]), ColorFiboExt, 1, STYLE_DASH, "");
            DrawLine(g_prefix+"DN_E"+(string)k, t_end, midnight, mid-(dist*ext[k]), ColorFiboExt, 1, STYLE_DASH, "");
         }
      }

      // 3. FIBO INTERNES (OTE) - MAINTENANT PROLONGÉS JUSQU'À MINUIT
      if(ShowFiboInt) {
         double intLevels[] = {0.618, 0.705, 0.786};
         for(int j=0; j<3; j++) {
            // Entre AM et AH (Zone Premium)
            double valIntH = mid + (dist * intLevels[j]);
            DrawLine(g_prefix+"INT_H"+(string)j, t_start, midnight, valIntH, ColorFiboInt, 1, STYLE_DOT, "");
            
            // Entre AM et AL (Zone Discount)
            double valIntL = mid - (dist * intLevels[j]);
            DrawLine(g_prefix+"INT_L"+(string)j, t_start, midnight, valIntL, ColorFiboInt, 1, STYLE_DOT, "");
         }
      }
   }
   return(rates_total);
}

void DrawBox(string name, datetime t1, datetime t2, double h, double l) {
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, h, t2, l);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_COLOR, ColorBox);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

void DrawLine(string name, datetime t1, datetime t2, double p, color c, int w, ENUM_LINE_STYLE s, string desc) {
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p, t2, p);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, name, OBJPROP_STYLE, s);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, name, OBJPROP_TEXT, desc);
}
