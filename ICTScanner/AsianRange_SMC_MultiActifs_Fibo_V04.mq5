#property indicator_chart_window
#property indicator_plots 0

//--- INPUTS
input group "Paramètres Session (Heures de PARIS)"
input int      StartHP        = 0;   // Heure début Paris (00h)
input int      EndHP          = 8;   // Heure fin Paris (08h)
input int      OffsetFTMO     = 1;   // FTMO est à +1h de Paris
input color    ColorBox       = C'40,65,65';

input group "Extensions Fibonacci"
input color    ColorFibo      = clrGray; 
input bool     ShowFibo       = true;    

//--- GLOBALS
string g_prefix = "TV_Sync_0008_";

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
{
   if(rates_total < 500) return(rates_total);

   // 1. Conversion Heures Paris -> Heures FTMO (Broker)
   // 00:00 Paris devient 01:00 FTMO
   // 08:00 Paris devient 09:00 FTMO
   int brokerStart = (StartHP + OffsetFTMO) % 24;
   int brokerEnd   = (EndHP + OffsetFTMO) % 24;

   datetime now = TimeCurrent();
   MqlDateTime dt_now;
   TimeToStruct(now, dt_now);

   // 2. Définition de la fenêtre temporelle pour AUJOURD'HUI
   MqlDateTime st = dt_now, et = dt_now;
   st.hour = brokerStart; st.min = 0; st.sec = 0;
   et.hour = brokerEnd;   et.min = 0; et.sec = 0;

   datetime t_start = StructToTime(st);
   datetime t_end   = StructToTime(et);

   // Si l'heure actuelle est avant la fin de session, on regarde la session qui vient de finir
   if(now < t_end) {
      t_start -= 86400;
      t_end   -= 86400;
   }

   // 3. Scan des bougies (Logique identique à TradingView)
   int idx_start = iBarShift(_Symbol, _Period, t_start);
   int idx_end   = iBarShift(_Symbol, _Period, t_end);

   double hSess = -1, lSess = 999999;
   
   // BOUCLE : On prend toutes les bougies dont l'heure d'ouverture
   // est >= 01:00 et < 09:00 (Heure FTMO)
   for(int i = idx_start; i > idx_end; i--) {
      double valH = iHigh(_Symbol, _Period, i);
      double valL = iLow(_Symbol, _Period, i);
      if(valH > hSess) hSess = valH;
      if(valL < lSess) lSess = valL;
   }

   if(hSess != -1) {
      double mid = (hSess + lSess) / 2.0;
      double dist = hSess - mid;

      // Prolongation vers minuit (clôture journée)
      MqlDateTime mdt = dt_now;
      mdt.hour = 23; mdt.min = 59; mdt.sec = 59;
      datetime midnight = StructToTime(mdt);

      // 4. Dessin des objets
      DrawBox(g_prefix+"RECT", t_start, t_end, hSess, lSess);
      DrawLine(g_prefix+"H", t_start, midnight, hSess, clrMediumAquamarine, 2, STYLE_SOLID, "AH: "+DoubleToString(hSess,_Digits));
      DrawLine(g_prefix+"L", t_start, midnight, lSess, clrMediumAquamarine, 2, STYLE_SOLID, "AL: "+DoubleToString(lSess,_Digits));
      DrawLine(g_prefix+"M", t_start, midnight, mid, clrOrange, 1, STYLE_DOT, "AM: "+DoubleToString(mid,_Digits));

      if(ShowFibo) {
         double levels[] = {1.618, 2.618, 3.618, 4.618, 5.618};
         for(int k=0; k<5; k++) {
            DrawLine(g_prefix+"UP"+(string)k, t_end, midnight, mid+(dist*levels[k]), ColorFibo, 1, STYLE_DASH, "");
            DrawLine(g_prefix+"DN"+(string)k, t_end, midnight, mid-(dist*levels[k]), ColorFibo, 1, STYLE_DASH, "");
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
