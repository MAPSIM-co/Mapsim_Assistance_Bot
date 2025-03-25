//+------------------------------------------------------------------+
//|                                     Bot_Assistance_Tarantula.mq5 |
//|                                  Copyright 2024, Tarantula Trade |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MAPSIM.co"
#property link      "https://www.Mapsim.xyz"
#property version   "23.22"

#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <ChartObjects\ChartObjectsTxtControls.mqh> // برای ایجاد کنترل‌های گرافیکی

#define HEXCHAR_TO_DECCHAR(h)  (h<=57 ? (h-48) : (h-55))
#define KEY_SIZE 32

string encryption_key = "765BC5720769C61677895D7563GHH0TM"; // کلید رمزنگاری
string active_code ="213250101";

//+------------------------------------------------------------------+
//| struct                                                            |
//+------------------------------------------------------------------+
CTrade trade;

//+------------------------------------------------------------------+
//| Input                                                            |
//+------------------------------------------------------------------+
// Expert properties

input string license_input_from_user = "Please Entry Your License"; // License
input string username_input_from_user = "Please Entry Your UserName"; // User Name 
input string password_input_from_user = "Please Entry Your Password"; // Password 
//+------------------------------------------------------------------+
input string Divider1 = "----------------------------"; // Managment TP,SL 

input double SL_Pips = 40.0;   // Stop Loss in pips
input double TP_Pips = 40.0;   // Take Profit in pips
input double lotSize_defult = 0.3; // Defult Lot/Contract Size
input double risk = 0.5; // Risk in Balance For Calculate Get Maximom Your (Lot/Contract) 
input double pip_value_contract = 100.0;   // Pip Value For Symbol (Index = 100 , Forex = 10)
input bool SL_active = true; // SL Automatic Active
input bool TP_active = true; // TP Automatic Active

input string Divider2 = "----------------------------"; // Managment Partail

input bool Parsall_active = true; // Partail Active
input bool Parsal_S1 = true; // Partail Step 1 Active
input bool Parsal_S2 = true; // Partail Step 2 Active
input bool Parsal_S3 = true; // Partail Step 3 Active
input int percenteg_volume_parsal_1 = 30; // Percenteg of Volume for Partail Step 1
input int percenteg_volume_parsal_2 = 50; // Percenteg of Volume for Partail Step 2
input int percenteg_volume_parsal_3 = 50; // Percenteg of Volume for Partail Step 3
input int Parsall_manually = 50; // Percenteg of Volume for Partail Manually

input string Divider3 = "----------------------------"; // Managment Bot Setting

input int AMPM = 15; // Count for Momentom in the Market

input double Active_AMPM = 1000 ;// Get Position Upper This Number Allow AMPM

input int MaxDailyTrades = 5; // Count Position Allow In Day

input bool Show_Calculate_Per_Trades = false; // Display the calculation of the required number of trades in the output

input string Divider4 = "----------------------------"; // Managment Information Box

input bool Show_Information_Box = true; // Display The Information Box In The Chart

input string Divider5 = "----------------------------"; // Managment Volume Box Titel

input int volume_box_xDistance_Titel = 10; // Volume Titel xDistance  
input int volume_box_yDistance_Titel = 30; // Volume Titel yDistance  
input int volume_box_Font_Size_Titel = 12; // Volume Titel Font Size 
input color volume_box_color_Titel = clrDarkGoldenrod ; // Volume Box Color 

input string Divider6 = "----------------------------";  // Managment Volume Box 

input int volume_box_width = 195; // Volume Box Width Size 
input int volume_box_height = 80; // Volume Box Height Size
input int volume_box_xDistance_Box = 10; // Volume Box xDistance  
input int volume_box_yDistance_Box = 70; // Volume Box yDistance  
//input int V_box_width_Box = 150; // Volume Box Width 

input int volume_box_Font_Size_Box = 14; // Volume Box Font Size 
input color volume_box_color_Box = clrGreenYellow ; // Volume Box Color 

input string Divider7 = "----------------------------";  // Managment Daily High & Low

input bool show_daily_high_low = true ; // Show Daily High & Low In Chart

input color highLine_Color = clrBlue; // Daily High Color 
input ENUM_LINE_STYLE highLine_Style = STYLE_DASHDOTDOT; // Daily High Line Type
input int highLine_Width = 3; // Daily High Line Width 

input color lowLine_Color = clrRed; // Daily Low Color 
input ENUM_LINE_STYLE lowLine_Style = STYLE_DASHDOTDOT; // Daily Low Line Type 
input int lowLine_Width = 3; // Daily Low Line Width 

input string Divider8 = "----------------------------";  // Managment Auto Break Even Mode

input bool Auto_Break_Even_Mode = false; // True = Automatic Close All Position In The Break Even Point

input double User_Bufer_Spread = 1; //Calculating the spread amount for safe exit Break Even

input string Divider9 = "----------------------------";  // Managment Candel Period

input int Max_candel_ = 60 ;// Max Candels For Period 

input string Divider10 = "----------------------------";  // Managment OB+

input bool Show_line_OB_Positive = true; // Show Line Shadow OB+
input color line_OB_Positive_Color = clrBlue; // Line Shadow OB+ Color 
input ENUM_LINE_STYLE line_OB_Positive_Style = STYLE_SOLID; // Line Shadow OB+ Line Type
input int line_OB_Positive_Width = 2; // Line Shadow OB+ Line Width 

input string Divider11 = "----------------------------";

input bool Show_Midel_of_shadow_OB_Positive = false; // Show Midel Line Shadow OB+
input color Midel_of_shadow_OB_Positive_Color = clrGoldenrod; // Midel Line Shadow OB+ Color 
input ENUM_LINE_STYLE Midel_of_shadow_OB_Positive_Style = STYLE_DASHDOTDOT; // Midel Line Shadow OB+ Line Type
input int Midel_of_shadow_OB_Positive_Width = 2; // Midel Line Shadow OB+ Line Width 

input string Divider12 = "----------------------------";  // Managment OB-

input bool Show_line_OB_Negative = true; // Show Line Shadow OB-
input color line_OB_Negative_Color = clrRed; // Line Shadow OB- Color 
input ENUM_LINE_STYLE line_OB_Negative_Style = STYLE_SOLID; // Line Shadow OB- Line Type
input int line_OB_Negative_Width = 2; // Line Shadow OB- Line Width 

input string Divider13 = "----------------------------";

input bool Show_Midel_of_shadow_OB_Negative = false; // Show Midel Line Shadow OB-
input color Midel_of_shadow_OB_Negative_Color = clrDeepSkyBlue; // Midel Line Shadow OB- Color 
input ENUM_LINE_STYLE Midel_of_shadow_OB_Negative_Style = STYLE_DASHDOTDOT; // Midel Line Shadow OB- Line Type
input int Midel_of_shadow_OB_Negative_Width = 2; // Midel Line Shadow OB- Line Width 




//+------------------------------------------------------------------+
//| Variabel                                                            |
//+------------------------------------------------------------------+
// ساختار اطلاعات کندل
struct Candle_Stick {
    double open_candel;  // قیمت باز شدن کندل
    double high_candel;  // بالاترین قیمت کندل
    double close_candel; // قیمت بسته شدن کندل
    double low_candel;   // پایین‌ترین قیمت کندل
    string type_candel;  // نوع کندل (Bullish یا Bearish)
};

Candle_Stick candel_last60[1440];

static double lastKafPrice = -1;
static double lastSaghfPrice = -1;
static int lastKafIndex = -1;
static int lastSaghfIndex = -1;


int Num_candels_period = 0;

bool pars_1 = false;
bool pars_2 = false;
bool pars_3 = false;
ulong last_ticket = 0;
ulong new_ticket = 0;
int index_positon =0;

double parsall_price_step1=0,parsall_price_step2=0,parsall_price_step3=0;

bool ctrlon = false; // وضعیت کلید کنترل
double lotSize = lotSize_defult; // حجم پیش‌فرض اولیه

bool Parsall_activeity_status = Parsall_active;

string decrypted_username, decrypted_password, decrypted_end_time, decrypted_active_code, decrypted_Account_login_number;
bool username_check_statuss, password_check_statuss, account_check_statuss, license_statuss;

bool Bot_RUN = true;

string filePath="TDAB_St_241010_.txt";
string signalFilePath ="213tdab20231001.txt";
string filePath_Day_Trade_Count = "MDTC.txt";

bool Device_status = false;

bool Device_stataus_show_message_connect = true , Device_stataus_show_message_disconnect=true;

double AMPM_BUY = 0;
double AMPM_SELL = 0;
double AMPM_Status = 0;

int tradeCountToday = 0;
string lastTradeDay = "";

double _Global_partial_lot = 0;

bool EQ_OnBreakeven = false ;//

//bool test_OnBreakeven = true; //Test EQ Variabel 

double VPT_c = 0.0 , buffer_c = 0.0 , Status_profit = 0.0;
    


//-------------------------------------------------------------------

// Function to calculate pip value based on asset
double PipValue() {
    return (SymbolInfoDouble(Symbol(), SYMBOL_POINT) * pip_value_contract);
}

// Function to calculate price levels based on pips and asset type
double CalculatePrice(double entry_price, double pips, bool is_buy) {
    double pip_value = PipValue();
    if (is_buy) {
        return entry_price + (pips * pip_value);
    } else {
        return entry_price - (pips * pip_value);
    }
}

// Main function
void OnTick() {

    OnTimer();
   
    
    if(!check_Run_paython_program())
    {
        Print("Bot Not Active .");
        return;
    }
    else
    {
        Num_candels_period = Max_candel_;
        Check_device_status();
        Get_candel_OHLC(candel_last60, Num_candels_period);
        check_Pivot_period();
        UpdateDailyTradeCount();
         //if(show_daily_high_low)
        //{
            DrawDailyHighLow();

        //}


        // زمان فعلی سرور
        //datetime currentTime = TimeCurrent();
        //Print("زمان سرور شما = ", currentTime);
        //Print("ربات دستیار در حال اجراست ...");

        if(PositionsTotal()==0)
        {
            pars_1 = false;
            pars_2 = false;
            pars_3 = false;

            EQ_OnBreakeven=false;
            VPT_c = 0.0 ;
            buffer_c = 0.0 ;
            Status_profit = 0.0;
            
            if (Parsall_active)
                Parsall_activeity_status = true;
            else
                Parsall_activeity_status = false;
        
            
            //Print_Important_Information_Chart();
        }
        
        if (PositionSelect(Symbol())) 
        {
            double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
            bool is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            double stopLoss = PositionGetDouble(POSITION_SL);
            double takeProfit = PositionGetDouble(POSITION_TP);
            


            // Check if SL is set for this specific trade
            if ((stopLoss <= 0 ) && SL_active) 
            {
                double sl_price = CalculatePrice(entry_price, SL_Pips, !is_buy);
                double tp_price = PositionGetDouble(POSITION_TP);//CalculatePrice(entry_price, TP_Pips, is_buy);
                
                ModifyStopLossAndTakeProfit(sl_price, tp_price);
            }

            // Check if TP is set for this specific trade
            if ((takeProfit <= 0) && TP_active) 
            {
                double sl_price = PositionGetDouble(POSITION_SL);//CalculatePrice(entry_price, SL_Pips, !is_buy);
                double tp_price = CalculatePrice(entry_price, TP_Pips, is_buy);
                
                ModifyStopLossAndTakeProfit(sl_price, tp_price);
            }
            
                    
            if(PositionsTotal()>1)
                Parsall_activeity_status=false;
            
            if(Parsall_activeity_status)
            {
                if(is_buy)
                {
                    GetNewStopLossForBuy(is_buy);
                }
                else
                {
                    GetNewStopLossForSell(!is_buy);
                }
            }

            if(Auto_Break_Even_Mode)
                EQ_OnBreakeven=true;

            if(PositionsTotal()>1 && !Parsall_activeity_status && EQ_OnBreakeven)
            {
                ClosePositionsOnBreakeven();
            }
        
        }

        if(Show_Information_Box)    
        {
            Print_Important_Information_Chart();
        }
        else
        {
            ObjectDelete(0, "Background");
            ObjectDelete(0, "Device_a_b_t_text");
            ObjectDelete(0, "Device_a_b_s_text");
            ObjectDelete(0, "Volume_text");
            ObjectDelete(0, "Risk_In_Balance_text");

            ObjectDelete(0, "Money_target_text");
            ObjectDelete(0, "Day_Trade_text");
            ObjectDelete(0, "Day_Trade_Status_text");
            ObjectDelete(0, "DailyHighText");
            ObjectDelete(0, "DailyLowText");
            ObjectDelete(0, "Avrage_Move_pips_Market_txt");
            ObjectDelete(0, "Avrage_Move_pips_Market_Status_txt");
            ObjectDelete(0, "spread_txt");
            ObjectDelete(0, "tp_pips_txt");
            ObjectDelete(0, "sl_pips_txt");
            ObjectDelete(0, "Parsall_status_txt");
            ObjectDelete(0, "OnBreakeven_status_text");

            ObjectDelete(0, "OnBreakeven_status");
            ObjectDelete(0, "vPT_text");
            ObjectDelete(0, "VPT_calculate");
            ObjectDelete(0, "Status_profit_text");
            ObjectDelete(0, "S_profit");
            ObjectDelete(0, "buffer_c_text");
            ObjectDelete(0, "Buffer_Point_Doller");
            ObjectDelete(0, "P_s1_txt");
            ObjectDelete(0, "P_s2_txt");
            ObjectDelete(0, "P_s3_txt");
        }

        if(Show_Calculate_Per_Trades)
        {
            CalculateDailyTrades();
        }
    }
    
    
}

// Function to modify SL and TP
void ModifyStopLossAndTakeProfit(double newStopLoss, double newTakeProfit ) {
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    double minStopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * PipValue();

    if (MathAbs(newStopLoss - PositionGetDouble(POSITION_PRICE_CURRENT)) >= minStopLevel &&
        MathAbs(newTakeProfit - PositionGetDouble(POSITION_PRICE_CURRENT)) >= minStopLevel) {
        
        request.action = TRADE_ACTION_SLTP;
        request.symbol = Symbol();
        request.sl = newStopLoss;
        request.tp = newTakeProfit;
        request.position = PositionGetInteger(POSITION_TICKET);

        if (!OrderSend(request, result)) {
            Print("Error modifying SL/TP: ", result.retcode);
        }
    } else {
        Print("SL/TP levels are too close to the current price. Adjusting...");
    }
}


void GetNewStopLossForBuy(bool is_buy )
{
    
    double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double tp_price = PositionGetDouble(POSITION_TP);//CalculatePrice(entry_price, TP_Pips, is_buy);
    double sl_price = PositionGetDouble(POSITION_SL);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

    double midel_tp_pips = (TP_Pips/2);
    //Print("currentPrice=",currentPrice);
    
    double midel_tp_price = CalculatePrice(entry_price, midel_tp_pips, is_buy);
    //Print("midel_tp_price=",midel_tp_price);


    double par1_price = (entry_price+midel_tp_price)/2;

    parsall_price_step1=par1_price;
    //Print("par1_price=",par1_price);

    double par2_price = midel_tp_price;
    parsall_price_step2=par2_price;
    //Print("par2_price=",par2_price);

    double par3_price = (midel_tp_price+tp_price)/2;
    parsall_price_step3=par3_price;
    //Print("par3_price=",par3_price);

   double new_SL = sl_price;
    
   
    if((currentPrice>=par1_price && currentPrice<par2_price) && (!pars_1) && (Parsal_S1))
    {
        //Print("Parsial-1 = Active");
        
        close_position_percentage(percenteg_volume_parsal_1);
        new_SL = entry_price;
        pars_1=true;
        ModifyStopLossAndTakeProfit(new_SL, tp_price);

        Print("Partail1 - Finish");
    } 
    else if((currentPrice>=par2_price && currentPrice<par3_price ) && (!pars_2) && (Parsal_S2))
    {
        //Print("Parsial-2 = Active");
        
        close_position_percentage(percenteg_volume_parsal_2);
        new_SL = par1_price;
        pars_2=true;
        ModifyStopLossAndTakeProfit(new_SL, tp_price);

        Print("Partail2 - Finish");
    } 
    else if((currentPrice>=par3_price && currentPrice<tp_price ) && (!pars_3) && (Parsal_S3))
    {
        //Print("Parsial-3 = Active"); 
        
        close_position_percentage(percenteg_volume_parsal_3);
        new_SL = par2_price;
        pars_3=true;
        ModifyStopLossAndTakeProfit(new_SL, tp_price);

        Print("Partail3 - Finish");
    } 
               
 
}



void GetNewStopLossForSell(bool is_buy)
{
    
    double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double tp_price = PositionGetDouble(POSITION_TP);//CalculatePrice(entry_price, TP_Pips, !is_buy);
    double sl_price = PositionGetDouble(POSITION_SL);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

    double midel_tp_pips = (TP_Pips/2);

    //Print("currentPrice=",currentPrice);
    
    double midel_tp_price = CalculatePrice(entry_price, midel_tp_pips, !is_buy);
    //Print("midel_tp_price=",midel_tp_price);


    double par1_price = (entry_price+midel_tp_price)/2;
    parsall_price_step1=par1_price;
    //Print("par1_price=",par1_price);

    double par2_price = midel_tp_price;
    parsall_price_step2=par2_price;
    //Print("par2_price=",par2_price);

    double par3_price = (midel_tp_price+tp_price)/2;
    parsall_price_step3=par3_price;
    //Print("par3_price=",par3_price);

    double new_SL=sl_price;
   
    if((currentPrice<=par1_price && currentPrice>par2_price) && (!pars_1) && (Parsal_S1))
    {
        close_position_percentage(percenteg_volume_parsal_1);
        new_SL = entry_price;
        pars_1=true;
        ModifyStopLossAndTakeProfit(new_SL, tp_price);

        Print("Partail1 - Finish");
    } 
    else if((currentPrice<=par2_price && currentPrice>par3_price) && (!pars_2) && (Parsal_S2))
    {
        close_position_percentage(percenteg_volume_parsal_2);
        new_SL = par1_price;
        pars_2=true;
        ModifyStopLossAndTakeProfit(new_SL, tp_price);

        Print("Partail2 - Finish");
    } 
    else if((currentPrice<=par3_price && currentPrice>tp_price) && (!pars_3) && (Parsal_S3))
    {
        close_position_percentage(percenteg_volume_parsal_3);
        new_SL = par2_price;
        pars_3=true;
        ModifyStopLossAndTakeProfit(new_SL, tp_price);

        Print("Partail3 - Finish");
    } 
               
 
}

void close_position_percentage(double percentage_partial )
{

  
   
    if(PositionsTotal()>0)
    {

        ulong ticket = PositionGetTicket(0);
        
        Print("ticket = ",IntegerToString(ticket));

        if (ticket <= 0)
        {

            int Error = GetLastError();
            string ErrorText = "21350001";
            Print("ERROR - Unable to select the position - ", Error);
            Print("ERROR - ", ErrorText);
        }
         //Print("position Volume =", DoubleToString(PositionGetDouble(POSITION_VOLUME)));
        if(PositionGetDouble(POSITION_VOLUME)<=0.2)
        {
            Print("Bot Can Not partial ... \n Availabel Volume <= 0.2 ");
            return;
        }
            
        
        double lotsToClose = (PositionGetDouble(POSITION_VOLUME) * percentage_partial) / 100.0;
        double roundedLots = MathRound(lotsToClose * 10) / 10;
        
         
        if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY))
        {
        
         //Print("PositionClosePartial in BUY *********");
                
          trade.PositionClosePartial(ticket,roundedLots,1);
            
        }
        else if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL))
        {
           //Print("PositionClosePartial in SELL *********");
           
           trade.PositionClosePartial(ticket,roundedLots,1);
        }
    }
    else
      Print("NO OPEN Position");
}


//+------------------------------------------------------------------+
//+------------------------------------------------------------------+  
// تابع ایجاد پس‌زمینه
bool createBackground_left_down()
{
    
    // دریافت ابعاد پنجره
    long width = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    long height = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

    // تنظیم مقادیر بر اساس ابعاد پنجره
    int xDistance = (int)(width * 0.01);  // 1% از عرض پنجره
    int yDistance = (int)(height * 0.33); // 10% از ارتفاع پنجره
    int xSize = (int)(width * 0.23);      // 50% از عرض پنجره
    int ySize = (int)(height * 0.33);     // 77% از ارتفاع پنجره

    ObjectCreate(0, "Background", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "Background", OBJPROP_CORNER, CORNER_LEFT_LOWER);
    ObjectSetInteger(0, "Background", OBJPROP_XDISTANCE, xDistance);
    ObjectSetInteger(0, "Background", OBJPROP_YDISTANCE, yDistance);
    ObjectSetInteger(0, "Background", OBJPROP_XSIZE, xSize);
    ObjectSetInteger(0, "Background", OBJPROP_YSIZE, ySize);
    ObjectSetInteger(0, "Background", OBJPROP_BGCOLOR, clrDarkKhaki);
    ObjectSetInteger(0, "Background", OBJPROP_BORDER_COLOR, clrBlueViolet);
    ObjectSetInteger(0, "Background", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "Background", OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, "Background", OBJPROP_BACK, false);
    ObjectSetInteger(0, "Background", OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, "Background", OBJPROP_HIDDEN, true);
    return (true);
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+  

void Print_Important_Information_Chart()
{

    // دریافت ابعاد پنجره
    long width = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    long height = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

    double dailyHigh = iHigh(Symbol(), PERIOD_D1, 0);
    double dailyLow = iLow(Symbol(), PERIOD_D1, 0);

    color P_s1_txt_color = clrBlack,P_s2_txt_color = clrBlack,P_s3_txt_color = clrBlack , status_device_color = clrRed , Avrage_Move_pips_Market_Status_txt_color = clrDarkViolet , Day_Trade_text_color = clrDarkViolet , S_profit_Color = clrDarkRed;
    
    string parsal_status = "" , status_device = "" ,Avrage_Move_pips_Market_Status_txt_ = "",Day_Trade_text_= "" , Sp_ ="";

    // ایجاد پس‌زمینه
    createBackground_left_down();
    
    
    if(Device_status)
    {
       status_device = "Connected";
       status_device_color = clrGreen;
    }
    else
    {
       status_device = "Not Connected";
       status_device_color = clrRed;
    }
            
   
      
    

     string Device_a_b_t = "Device Assistance Bot = ";
     ObjectCreate(0, "Device_a_b_t_text", OBJ_LABEL, 0, 0, 0);
     ObjectSetInteger(0, "Device_a_b_t_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
     ObjectSetInteger(0, "Device_a_b_t_text", OBJPROP_XDISTANCE, (int)(width * 0.02));
     ObjectSetInteger(0, "Device_a_b_t_text", OBJPROP_YDISTANCE, (int)(height * 0.32));
     ObjectSetInteger(0, "Device_a_b_t_text", OBJPROP_COLOR, clrBlack);
     ObjectSetString(0, "Device_a_b_t_text", OBJPROP_TEXT, Device_a_b_t);
     

     string Device_a_b_s = status_device;
     ObjectCreate(0, "Device_a_b_s_text", OBJ_LABEL, 0, 0, 0);
     ObjectSetInteger(0, "Device_a_b_s_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
     ObjectSetInteger(0, "Device_a_b_s_text", OBJPROP_XDISTANCE, (int)(width * 0.155));
     ObjectSetInteger(0, "Device_a_b_s_text", OBJPROP_YDISTANCE, (int)(height * 0.32));
     ObjectSetInteger(0, "Device_a_b_s_text", OBJPROP_COLOR, status_device_color);
     ObjectSetString(0, "Device_a_b_s_text", OBJPROP_TEXT, Device_a_b_s);
     

    string Volume_string = "max.V = " + DoubleToString(Managment_volume(),2);
     ObjectCreate(0, "Volume_text", OBJ_LABEL, 0, 0, 0);
     ObjectSetInteger(0, "Volume_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
     ObjectSetInteger(0, "Volume_text", OBJPROP_XDISTANCE, (int)(width * 0.156));
     ObjectSetInteger(0, "Volume_text", OBJPROP_YDISTANCE, (int)(height * 0.29));
     ObjectSetInteger(0, "Volume_text", OBJPROP_COLOR, clrRoyalBlue);
     ObjectSetString(0, "Volume_text", OBJPROP_TEXT, Volume_string);

    string Risk_in_Balance = "Risk ="+DoubleToString(risk,2)+"%";
     ObjectCreate(0, "Risk_In_Balance_text", OBJ_LABEL, 0, 0, 0);
     ObjectSetInteger(0, "Risk_In_Balance_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
     ObjectSetInteger(0, "Risk_In_Balance_text", OBJPROP_XDISTANCE, (int)(width * 0.156));
     ObjectSetInteger(0, "Risk_In_Balance_text", OBJPROP_YDISTANCE, (int)(height * 0.26));
     ObjectSetInteger(0, "Risk_In_Balance_text", OBJPROP_COLOR, clrDarkSlateBlue);
     ObjectSetString(0, "Risk_In_Balance_text", OBJPROP_TEXT, Risk_in_Balance);

     string Money_target_text = "$ = " + DoubleToString(Managment_Target_Money(Managment_volume()),2);
     ObjectCreate(0, "Money_target_text", OBJ_LABEL, 0, 0, 0);
     ObjectSetInteger(0, "Money_target_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
     ObjectSetInteger(0, "Money_target_text", OBJPROP_XDISTANCE, (int)(width * 0.156));
     ObjectSetInteger(0, "Money_target_text", OBJPROP_YDISTANCE, (int)(height * 0.23));
     ObjectSetInteger(0, "Money_target_text", OBJPROP_COLOR, clrDarkViolet);
     ObjectSetString(0, "Money_target_text", OBJPROP_TEXT, Money_target_text);
     
     string Day_Trade_text = "CDT = " + IntegerToString(tradeCountToday)+ " OF "+IntegerToString(MaxDailyTrades);//    //CalculateDailyTrades()
     ObjectCreate(0, "Day_Trade_text", OBJ_LABEL, 0, 0, 0);
     ObjectSetInteger(0, "Day_Trade_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
     ObjectSetInteger(0, "Day_Trade_text", OBJPROP_XDISTANCE, (int)(width * 0.156));
     ObjectSetInteger(0, "Day_Trade_text", OBJPROP_YDISTANCE, (int)(height * 0.2));
     ObjectSetInteger(0, "Day_Trade_text", OBJPROP_COLOR, clrBlack);
     ObjectSetString(0, "Day_Trade_text", OBJPROP_TEXT, Day_Trade_text);
     
     if (tradeCountToday >= MaxDailyTrades)
    {
       Day_Trade_text_ = "X";
       Day_Trade_text_color = clrRed;
    }
    else
    {
       Day_Trade_text_ =  "√";
       Day_Trade_text_color = clrGreen;
    }


     string Day_Trade_Status_text = Day_Trade_text_;
     ObjectCreate(0, "Day_Trade_Status_text", OBJ_LABEL, 0, 0, 0);
     ObjectSetInteger(0, "Day_Trade_Status_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
     ObjectSetInteger(0, "Day_Trade_Status_text", OBJPROP_XDISTANCE, (int)(width * 0.2255));
     ObjectSetInteger(0, "Day_Trade_Status_text", OBJPROP_YDISTANCE, (int)(height * 0.21));
     ObjectSetInteger(0, "Day_Trade_Status_text", OBJPROP_COLOR, Day_Trade_text_color);
     ObjectSetString(0, "Day_Trade_Status_text", OBJPROP_TEXT, Day_Trade_Status_text);
     ObjectSetInteger(0,"Day_Trade_Status_text",OBJPROP_FONTSIZE, 16);
     

    string highText = "Daily High = " + DoubleToString(dailyHigh, _Digits);
     ObjectCreate(0, "DailyHighText", OBJ_LABEL, 0, 0, 0);
     ObjectSetInteger(0, "DailyHighText", OBJPROP_CORNER, CORNER_LEFT_LOWER);
     ObjectSetInteger(0, "DailyHighText", OBJPROP_XDISTANCE, (int)(width * 0.02));
     ObjectSetInteger(0, "DailyHighText", OBJPROP_YDISTANCE, (int)(height * 0.28));
     ObjectSetInteger(0, "DailyHighText", OBJPROP_COLOR, clrDarkGreen);
     ObjectSetString(0, "DailyHighText", OBJPROP_TEXT, highText);

     string lowText = "Daily Low = " + DoubleToString(dailyLow, _Digits);
     ObjectCreate(0, "DailyLowText", OBJ_LABEL, 0, 0, 0);
     ObjectSetInteger(0, "DailyLowText", OBJPROP_CORNER, CORNER_LEFT_LOWER);
     ObjectSetInteger(0, "DailyLowText", OBJPROP_XDISTANCE, (int)(width * 0.02));
     ObjectSetInteger(0, "DailyLowText", OBJPROP_YDISTANCE, (int)(height * 0.24));
     ObjectSetInteger(0, "DailyLowText", OBJPROP_COLOR, clrRed);
     ObjectSetString(0, "DailyLowText", OBJPROP_TEXT, lowText);
     
     
     // ایجاد متن Move pips avrage قیمت
     string Avrage_Move_pips_Market_txt = "AMPM-"+IntegerToString(AMPM) +" = " + DoubleToString(CalculateAveragePipMovement(AMPM, false), _Digits);
     ObjectCreate(0, "Avrage_Move_pips_Market_txt", OBJ_LABEL, 0, 0, 0);
     ObjectSetInteger(0, "Avrage_Move_pips_Market_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
     ObjectSetInteger(0, "Avrage_Move_pips_Market_txt", OBJPROP_XDISTANCE, (int)(width * 0.02));
     ObjectSetInteger(0, "Avrage_Move_pips_Market_txt", OBJPROP_YDISTANCE, (int)(height * 0.2));
     ObjectSetInteger(0, "Avrage_Move_pips_Market_txt", OBJPROP_COLOR, clrDarkViolet);
     ObjectSetString(0, "Avrage_Move_pips_Market_txt", OBJPROP_TEXT, Avrage_Move_pips_Market_txt);

    AMPM_Status = CalculateAveragePipMovement(AMPM, false); 

    if(AMPM_Status>=Active_AMPM)
    {
       Avrage_Move_pips_Market_Status_txt_ = "√";
       Avrage_Move_pips_Market_Status_txt_color = clrGreen;
    }
    else
    {
       Avrage_Move_pips_Market_Status_txt_ = "X";
       Avrage_Move_pips_Market_Status_txt_color = clrRed;
    }


     string Avrage_Move_pips_Market_Status_txt = Avrage_Move_pips_Market_Status_txt_;
     ObjectCreate(0, "Avrage_Move_pips_Market_Status_txt", OBJ_LABEL, 0, 0, 0);
     ObjectSetInteger(0, "Avrage_Move_pips_Market_Status_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
     ObjectSetInteger(0, "Avrage_Move_pips_Market_Status_txt", OBJPROP_XDISTANCE, (int)(width * 0.125));
     ObjectSetInteger(0, "Avrage_Move_pips_Market_Status_txt", OBJPROP_YDISTANCE, (int)(height * 0.21));
     ObjectSetInteger(0, "Avrage_Move_pips_Market_Status_txt", OBJPROP_COLOR, Avrage_Move_pips_Market_Status_txt_color);
     ObjectSetString(0, "Avrage_Move_pips_Market_Status_txt", OBJPROP_TEXT, Avrage_Move_pips_Market_Status_txt);
     ObjectSetInteger(0,"Avrage_Move_pips_Market_Status_txt",OBJPROP_FONTSIZE, 16);
    
 
    string spread_txt = "Spread = " +IntegerToString(SymbolInfoInteger (_Symbol, SYMBOL_SPREAD),1);
    ObjectCreate(0, "spread_txt", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "spread_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
    ObjectSetInteger(0, "spread_txt", OBJPROP_XDISTANCE, (int)(width * 0.02));
    ObjectSetInteger(0, "spread_txt", OBJPROP_YDISTANCE, (int)(height * 0.04));
    ObjectSetInteger(0, "spread_txt", OBJPROP_COLOR,clrDarkSlateBlue);
    ObjectSetString(0, "spread_txt", OBJPROP_TEXT, spread_txt);

    string tp_pips_txt = "TP Pips = " +DoubleToString(TP_Pips,1);
    ObjectCreate(0, "tp_pips_txt", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "tp_pips_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
    ObjectSetInteger(0, "tp_pips_txt", OBJPROP_XDISTANCE, (int)(width * 0.02));
    ObjectSetInteger(0, "tp_pips_txt", OBJPROP_YDISTANCE, (int)(height * 0.08));
    ObjectSetInteger(0, "tp_pips_txt", OBJPROP_COLOR,clrDarkSlateBlue);
    ObjectSetString(0, "tp_pips_txt", OBJPROP_TEXT, tp_pips_txt);

    string sl_pips_txt = "SL Pips = " +DoubleToString(SL_Pips,1);
    ObjectCreate(0, "sl_pips_txt", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "sl_pips_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
    ObjectSetInteger(0, "sl_pips_txt", OBJPROP_XDISTANCE, (int)(width * 0.02));
    ObjectSetInteger(0, "sl_pips_txt", OBJPROP_YDISTANCE, (int)(height * 0.12));
    ObjectSetInteger(0, "sl_pips_txt", OBJPROP_COLOR,clrDarkSlateBlue);
    ObjectSetString(0, "sl_pips_txt", OBJPROP_TEXT, sl_pips_txt);


    if(Parsall_active)
    {
        if(!Parsall_activeity_status)
            parsal_status = "False";
        else
            parsal_status = "True";
    }
    else
      parsal_status = "False";
      
    string Parsall_status_txt = "Parsall = " +parsal_status;
    ObjectCreate(0, "Parsall_status_txt", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "Parsall_status_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
    ObjectSetInteger(0, "Parsall_status_txt", OBJPROP_XDISTANCE, (int)(width * 0.02));
    ObjectSetInteger(0, "Parsall_status_txt", OBJPROP_YDISTANCE, (int)(height * 0.16));
    ObjectSetInteger(0, "Parsall_status_txt", OBJPROP_COLOR,clrDarkSlateBlue);
    ObjectSetString(0, "Parsall_status_txt", OBJPROP_TEXT, Parsall_status_txt);


    if(!Parsall_activeity_status && EQ_OnBreakeven)
    //if(test_OnBreakeven)
    {
        string OnBreakeven_status_text = "EQ-P Mode = ";
        ObjectCreate(0, "OnBreakeven_status_text", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "OnBreakeven_status_text", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "OnBreakeven_status_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "OnBreakeven_status_text", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "OnBreakeven_status_text", OBJPROP_YDISTANCE, (int)(height * 0.16));
        ObjectSetInteger(0, "OnBreakeven_status_text", OBJPROP_COLOR,clrBlueViolet);
        ObjectSetString(0, "OnBreakeven_status_text", OBJPROP_TEXT, OnBreakeven_status_text);

        string OnBreakeven_status = "Active";
        ObjectCreate(0, "OnBreakeven_status", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "OnBreakeven_status", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "OnBreakeven_status", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "OnBreakeven_status", OBJPROP_XDISTANCE, (int)(width * 0.185));
        ObjectSetInteger(0, "OnBreakeven_status", OBJPROP_YDISTANCE, (int)(height * 0.16));
        ObjectSetInteger(0, "OnBreakeven_status", OBJPROP_COLOR,clrDarkGreen);
        ObjectSetString(0, "OnBreakeven_status", OBJPROP_TEXT, OnBreakeven_status);

        //-------------------------------------------------------------------------

        string vPT_text = "PVT = ";
        ObjectCreate(0, "vPT_text", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "vPT_text", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "vPT_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "vPT_text", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "vPT_text", OBJPROP_YDISTANCE, (int)(height * 0.12));
        ObjectSetInteger(0, "vPT_text", OBJPROP_COLOR,clrBlueViolet);
        ObjectSetString(0, "vPT_text", OBJPROP_TEXT, vPT_text);

        VPT_c = NormalizeDouble(VPT_c, 2);
        string VPT_calculate = DoubleToString(VPT_c,2);
        ObjectCreate(0, "VPT_calculate", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "VPT_calculate", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "VPT_calculate", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "VPT_calculate", OBJPROP_XDISTANCE, (int)(width * 0.15));
        ObjectSetInteger(0, "VPT_calculate", OBJPROP_YDISTANCE, (int)(height * 0.12));
        ObjectSetInteger(0, "VPT_calculate", OBJPROP_COLOR,clrRoyalBlue);
        ObjectSetString(0, "VPT_calculate", OBJPROP_TEXT, VPT_calculate);

        //---------------------------------------------------------------------------

        
        if(Status_profit>=0)
        {
            S_profit_Color = clrDarkGreen;
            Status_profit = NormalizeDouble(Status_profit, 2);
            Sp_ = DoubleToString(Status_profit,2);
        }
        else
        {
            S_profit_Color = clrDarkRed;
            Status_profit = NormalizeDouble(Status_profit, 2);
            Sp_ = " "+DoubleToString(Status_profit,2);
        }

        string Status_profit_text = "PS = ";
        ObjectCreate(0, "Status_profit_text", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "Status_profit_text", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "Status_profit_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "Status_profit_text", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "Status_profit_text", OBJPROP_YDISTANCE, (int)(height * 0.08));
        ObjectSetInteger(0, "Status_profit_text", OBJPROP_COLOR,clrBlueViolet);
        ObjectSetString(0, "Status_profit_text", OBJPROP_TEXT, Status_profit_text);

        string S_profit = Sp_;
        ObjectCreate(0, "S_profit", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "S_profit", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "S_profit", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "S_profit", OBJPROP_XDISTANCE, (int)(width * 0.15));
        ObjectSetInteger(0, "S_profit", OBJPROP_YDISTANCE, (int)(height * 0.08));
        ObjectSetInteger(0, "S_profit", OBJPROP_COLOR,S_profit_Color);
        ObjectSetString(0, "S_profit", OBJPROP_TEXT, S_profit);
        ObjectSetInteger(0,"S_profit",OBJPROP_FONTSIZE, 13);

        //---------------------------------------------------------------------------

        
        string buffer_c_text = "BP-$ = ";
        ObjectCreate(0, "buffer_c_text", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "buffer_c_text", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "buffer_c_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "buffer_c_text", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "buffer_c_text", OBJPROP_YDISTANCE, (int)(height * 0.04));
        ObjectSetInteger(0, "buffer_c_text", OBJPROP_COLOR,clrBlueViolet);
        ObjectSetString(0, "buffer_c_text", OBJPROP_TEXT, buffer_c_text);

        buffer_c = NormalizeDouble(buffer_c, 2);
        string Buffer_Point_Doller = DoubleToString(buffer_c,2);
        ObjectCreate(0, "Buffer_Point_Doller", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "Buffer_Point_Doller", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "Buffer_Point_Doller", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "Buffer_Point_Doller", OBJPROP_XDISTANCE, (int)(width * 0.15));
        ObjectSetInteger(0, "Buffer_Point_Doller", OBJPROP_YDISTANCE, (int)(height * 0.04));
        ObjectSetInteger(0, "Buffer_Point_Doller", OBJPROP_COLOR,clrDarkSlateBlue);
        ObjectSetString(0, "Buffer_Point_Doller", OBJPROP_TEXT, Buffer_Point_Doller);

        //---------------------------------------------------------------------------
        string P_s1_txt = " ";
        ObjectCreate(0, "P_s1_txt", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "P_s1_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "P_s1_txt", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "P_s1_txt", OBJPROP_YDISTANCE, (int)(height * 0.16));
        ObjectSetInteger(0, "P_s1_txt", OBJPROP_COLOR,P_s1_txt_color);
        ObjectSetString(0, "P_s1_txt", OBJPROP_TEXT, P_s1_txt);

        string P_s2_txt = " ";
        ObjectCreate(0, "P_s2_txt", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "P_s2_txt", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "P_s2_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "P_s2_txt", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "P_s2_txt", OBJPROP_YDISTANCE, (int)(height * 0.1));
        ObjectSetInteger(0, "P_s2_txt", OBJPROP_COLOR,P_s2_txt_color);
        ObjectSetString(0, "P_s2_txt", OBJPROP_TEXT, P_s2_txt);

        string P_s3_txt = " ";
        ObjectCreate(0, "P_s3_txt", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "P_s3_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "P_s3_txt", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "P_s3_txt", OBJPROP_YDISTANCE, (int)(height * 0.04));
        ObjectSetInteger(0, "P_s3_txt", OBJPROP_COLOR,P_s3_txt_color);
        ObjectSetString(0, "P_s3_txt", OBJPROP_TEXT, P_s3_txt);

    }
    else
    {

        string OnBreakeven_status_text = " ";
        ObjectCreate(0, "OnBreakeven_status_text", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "OnBreakeven_status_text", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "OnBreakeven_status_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "OnBreakeven_status_text", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "OnBreakeven_status_text", OBJPROP_YDISTANCE, (int)(height * 0.1));
        ObjectSetInteger(0, "OnBreakeven_status_text", OBJPROP_COLOR,clrBlueViolet);
        ObjectSetString(0, "OnBreakeven_status_text", OBJPROP_TEXT, OnBreakeven_status_text);

        string OnBreakeven_status = " ";
        ObjectCreate(0, "OnBreakeven_status", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "OnBreakeven_status", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "OnBreakeven_status", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "OnBreakeven_status", OBJPROP_XDISTANCE, (int)(width * 0.18));
        ObjectSetInteger(0, "OnBreakeven_status", OBJPROP_YDISTANCE, (int)(height * 0.1));
        ObjectSetInteger(0, "OnBreakeven_status", OBJPROP_COLOR,clrDarkGreen);
        ObjectSetString(0, "OnBreakeven_status", OBJPROP_TEXT, OnBreakeven_status);

         //-------------------------------------------------------------------------

        string vPT_text = " ";
        ObjectCreate(0, "vPT_text", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "vPT_text", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "vPT_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "vPT_text", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "vPT_text", OBJPROP_YDISTANCE, (int)(height * 0.12));
        ObjectSetInteger(0, "vPT_text", OBJPROP_COLOR,clrBlueViolet);
        ObjectSetString(0, "vPT_text", OBJPROP_TEXT, vPT_text);

        string VPT_calculate = " ";
        ObjectCreate(0, "VPT_calculate", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "VPT_calculate", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "VPT_calculate", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "VPT_calculate", OBJPROP_XDISTANCE, (int)(width * 0.15));
        ObjectSetInteger(0, "VPT_calculate", OBJPROP_YDISTANCE, (int)(height * 0.12));
        ObjectSetInteger(0, "VPT_calculate", OBJPROP_COLOR,clrRoyalBlue);
        ObjectSetString(0, "VPT_calculate", OBJPROP_TEXT, VPT_calculate);

        //---------------------------------------------------------------------------

        string Status_profit_text = " ";
        ObjectCreate(0, "Status_profit_text", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "Status_profit_text", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "Status_profit_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "Status_profit_text", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "Status_profit_text", OBJPROP_YDISTANCE, (int)(height * 0.08));
        ObjectSetInteger(0, "Status_profit_text", OBJPROP_COLOR,clrBlueViolet);
        ObjectSetString(0, "Status_profit_text", OBJPROP_TEXT, Status_profit_text);

        string S_profit = " ";
        ObjectCreate(0, "S_profit", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "S_profit", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "S_profit", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "S_profit", OBJPROP_XDISTANCE, (int)(width * 0.15));
        ObjectSetInteger(0, "S_profit", OBJPROP_YDISTANCE, (int)(height * 0.08));
        ObjectSetInteger(0, "S_profit", OBJPROP_COLOR,clrDarkGreen);
        ObjectSetString(0, "S_profit", OBJPROP_TEXT, S_profit);

        //---------------------------------------------------------------------------

        
        string buffer_c_text = " ";
        ObjectCreate(0, "buffer_c_text", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "buffer_c_text", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "buffer_c_text", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "buffer_c_text", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "buffer_c_text", OBJPROP_YDISTANCE, (int)(height * 0.04));
        ObjectSetInteger(0, "buffer_c_text", OBJPROP_COLOR,clrBlueViolet);
        ObjectSetString(0, "buffer_c_text", OBJPROP_TEXT, buffer_c_text);

        string Buffer_Point_Doller = " ";
        ObjectCreate(0, "Buffer_Point_Doller", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "Buffer_Point_Doller", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "Buffer_Point_Doller", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "Buffer_Point_Doller", OBJPROP_XDISTANCE, (int)(width * 0.15));
        ObjectSetInteger(0, "Buffer_Point_Doller", OBJPROP_YDISTANCE, (int)(height * 0.04));
        ObjectSetInteger(0, "Buffer_Point_Doller", OBJPROP_COLOR,clrDarkGreen);
        ObjectSetString(0, "Buffer_Point_Doller", OBJPROP_TEXT, Buffer_Point_Doller);

        //---------------------------------------------------------------------------

        if (pars_1 == true)
        P_s1_txt_color= clrRed;
        else
            P_s1_txt_color = clrGreen;
            
        if(PositionsTotal()==0)
        {
            parsall_price_step1=0;
            parsall_price_step2=0;
            parsall_price_step3=0;
        
        }

        string P_s1_txt = "P1-"+IntegerToString(percenteg_volume_parsal_1)+"% = " + DoubleToString(parsall_price_step1,2) ;
        ObjectCreate(0, "P_s1_txt", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "P_s1_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "P_s1_txt", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "P_s1_txt", OBJPROP_YDISTANCE, (int)(height * 0.16));
        ObjectSetInteger(0, "P_s1_txt", OBJPROP_COLOR,P_s1_txt_color);
        ObjectSetString(0, "P_s1_txt", OBJPROP_TEXT, P_s1_txt);

        if (pars_2 == true)
            P_s2_txt_color= clrRed;
        else
            P_s2_txt_color = clrGreen;

        string P_s2_txt = "P2-"+IntegerToString(percenteg_volume_parsal_2)+"% = " + DoubleToString(parsall_price_step2,2);
        ObjectCreate(0, "P_s2_txt", OBJ_LABEL, 0, 0, 0);
        ObjectCreate(0, "P_s2_txt", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "P_s2_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "P_s2_txt", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "P_s2_txt", OBJPROP_YDISTANCE, (int)(height * 0.1));
        ObjectSetInteger(0, "P_s2_txt", OBJPROP_COLOR,P_s2_txt_color);
        ObjectSetString(0, "P_s2_txt", OBJPROP_TEXT, P_s2_txt);

        if (pars_3 == true)
            P_s3_txt_color= clrRed;
        else
            P_s3_txt_color = clrGreen;

        string P_s3_txt = "P3-"+IntegerToString(percenteg_volume_parsal_3)+"% = " + DoubleToString(parsall_price_step3,2);
        ObjectCreate(0, "P_s3_txt", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "P_s3_txt", OBJPROP_CORNER, CORNER_LEFT_LOWER);
        ObjectSetInteger(0, "P_s3_txt", OBJPROP_XDISTANCE, (int)(width * 0.115));
        ObjectSetInteger(0, "P_s3_txt", OBJPROP_YDISTANCE, (int)(height * 0.04));
        ObjectSetInteger(0, "P_s3_txt", OBJPROP_COLOR,P_s3_txt_color);
        ObjectSetString(0, "P_s3_txt", OBJPROP_TEXT, P_s3_txt);


    }


    
}


//+------------------------------------------------------------------+
//| Function to calculate average pip movement of the last n candles |
//+------------------------------------------------------------------+
double CalculateAveragePipMovement(int numCandles , bool write_to_log)
{
    double totalPipMovement = 0.0;
    for (int i = 1; i <= numCandles; i++)
    {
        double high = iHigh(NULL, 0, i);
        double low = iLow(NULL, 0, i);
        totalPipMovement += (high - low) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    }
    double averagePipMovement = totalPipMovement / numCandles;
    string avgMovementMsg = "میانگین حرکت بازار در تعداد " + IntegerToString(numCandles) + " کندل اخیر : " + DoubleToString(averagePipMovement, 2);
    //Print(avgMovementMsg);
    //if(write_to_log)
        //WriteLog(avgMovementMsg);
    return averagePipMovement;
}


// ایجاد فیلد ورودی بزرگ‌تر برای حجم
void CreateVolumeInputPanel()
{

    // تنظیم مقادیر بر اساس ابعاد پنجره

    //string Volume_string = DoubleToString(Managment_volume(),2);

    // ایجاد عنوان پنجره
    if (!ObjectCreate(0, "VolumeTitle", OBJ_LABEL, 0, 0, 0))
        Print("Failed to create title label");
    ObjectSetInteger(0, "VolumeTitle", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, "VolumeTitle", OBJPROP_XDISTANCE, volume_box_xDistance_Titel);//10
    ObjectSetInteger(0, "VolumeTitle", OBJPROP_YDISTANCE, volume_box_yDistance_Titel);//30
    ObjectSetInteger(0, "VolumeTitle", OBJPROP_FONTSIZE, volume_box_Font_Size_Titel);//12
    ObjectSetString(0, "VolumeTitle", OBJPROP_TEXT, "Enter Volume:");
    ObjectSetInteger(0, "VolumeTitle", OBJPROP_COLOR, volume_box_color_Titel);//clrDarkGoldenrod


    // Max Lot/Contract
    /*
    if (!ObjectCreate(0, "Volume_MAX", OBJ_LABEL, 0, 0, 0))
        Print("Failed to create Volume_MAX");
    ObjectSetInteger(0, "Volume_MAX", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, "Volume_MAX", OBJPROP_XDISTANCE, 230);
    ObjectSetInteger(0, "Volume_MAX", OBJPROP_YDISTANCE, 30);
    ObjectSetInteger(0, "Volume_MAX", OBJPROP_FONTSIZE, 12);
    ObjectSetString(0, "Volume_MAX", OBJPROP_TEXT, "(Max VO. "+Volume_string+" ) :");
    ObjectSetInteger(0, "Volume_MAX", OBJPROP_COLOR, clrRed);
   */


    // ایجاد فیلد ورودی بزرگ‌تر برای حجم
    if (!ObjectCreate(0, "VolumeInput", OBJ_EDIT, 0, 0, 0))
        Print("Failed to create Volume input box");
    ObjectSetInteger(0, "VolumeInput", OBJPROP_XSIZE, volume_box_width);//195
    ObjectSetInteger(0, "VolumeInput", OBJPROP_YSIZE, volume_box_height);//80
    ObjectSetInteger(0, "VolumeInput", OBJPROP_STYLE, BORDER_RAISED);
    ObjectSetInteger(0, "VolumeInput", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, "VolumeInput", OBJPROP_XDISTANCE, volume_box_xDistance_Box);//10
    ObjectSetInteger(0, "VolumeInput", OBJPROP_YDISTANCE, volume_box_yDistance_Box); //70
    //ObjectSetInteger(0, "VolumeInput", OBJPROP_WIDTH, V_box_width_Box); //150
    ObjectSetInteger(0, "VolumeInput", OBJPROP_COLOR, volume_box_color_Box );//clrGreenYellow
    ObjectSetString(0, "VolumeInput", OBJPROP_TEXT, DoubleToString(lotSize, 2)); // مقدار اولیه حجم
    ObjectSetInteger(0, "VolumeInput", OBJPROP_FONTSIZE, volume_box_Font_Size_Box);
    
}
//------------------------------------------------------------------------------------/
    // رویداد کند تر اجرا میشود چون تابع تغییر وضعیت کنترل جداگانه فراخوانی میشود
//------------------------------------------------------------------------------------/
// // تابع تغییر وضعیت کنترل
// void ToggleCtrl() {
//     ctrlon = !ctrlon; // تغییر وضعیت کلید کنترل
// }

// تابع اصلی برای رویدادهای چارت
// void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
// {
//     if (id == CHARTEVENT_OBJECT_ENDEDIT && sparam == "VolumeInput") // زمانی که کاربر حجم را در فیلد وارد و تایید می‌کند
//     {
//         // به‌روزرسانی مقدار lotSize با مقدار ورودی کاربر
//         lotSize = StringToDouble(ObjectGetString(0, "VolumeInput", OBJPROP_TEXT));
//         Print("Volume updated to: ", lotSize);
//     }

//     if (id == CHARTEVENT_KEYDOWN) // اگر رویداد فشردن کلید باشد
//     {
//         if (lparam == 17) // اگر کلید Control فشرده شده باشد
//             ToggleCtrl();

//         if (ctrlon) // بررسی وضعیت فعال بودن Control
//         {
//             if (lparam == 49) // اگر Control+1 فشرده شده باشد
//             {
//                 // باز کردن پوزیشن خرید با حجم وارد شده
//                 if (trade.Buy(lotSize))
//                     Print("Buy position opened with volume: ", lotSize);
//                 else
//                     Print("Failed to open Buy position");
//             }
//             else if (lparam == 50) // اگر Control+3 فشرده شده باشد
//             {
//                 // باز کردن پوزیشن فروش با حجم وارد شده
//                 if (trade.Sell(lotSize))
//                     Print("Sell position opened with volume: ", lotSize);
//                 else
//                     Print("Failed to open Sell position");
//             }
//             else if (lparam == 48) // اگر Control+0 فشرده شده باشد
//             {
//                 for(int cnt = PositionsTotal()-1; cnt >= 0 && !IsStopped(); cnt-- )
//                 {
//                     if(PositionGetTicket(cnt))
//                     {
//                         trade.PositionClose(PositionGetInteger(POSITION_TICKET),100);
//                         uint code = trade.ResultRetcode();
//                         Print(IntegerToString(code));
//                     }
//                 }
//             }
//         }
//     }
// }

//--------------------------------------------------------------------------------------------/
//                        *********************************************
//--------------------------------------------------------------------------------------------/

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    static bool ctrlPressed = false;  // متغیر وضعیت کلید کنترل

    if(!check_Run_paython_program())
    {
        Print("Bot cannot get Position from Market ...");
        return;
    }
    else
    {

        if (id == CHARTEVENT_OBJECT_ENDEDIT && sparam == "VolumeInput") // بررسی تغییر حجم ورودی
        {
            lotSize = StringToDouble(ObjectGetString(0, "VolumeInput", OBJPROP_TEXT));
            Print("Volume updated to: ", lotSize);
        }

        if (id == CHARTEVENT_KEYDOWN) // بررسی وضعیت کلیدها    || id == CHARTEVENT_KEYUP
        {
            if (lparam == 17) // کلید Control
            {
                ctrlPressed = (id == CHARTEVENT_KEYDOWN);  // بروزرسانی وضعیت Control
            }
            
            if (ctrlPressed && id == CHARTEVENT_KEYDOWN) // در صورت فشرده بودن Control و یک کلید دیگر
            {
                if (lparam == 49) // اگر Control+1 فشرده شده باشد
                {
                    AMPM_BUY = CalculateAveragePipMovement(AMPM, false);

                    Read_Day_Trade_Count_From_File();

                    if (tradeCountToday >= MaxDailyTrades)
                    {
                        Print("Your trading limit for today has been exceeded!");
                        return ;
                    }
                    else
                    {
                        if(AMPM_BUY>=Active_AMPM)
                        {
                            if (trade.Buy(lotSize))
                            {
                                Print("Buy position opened with volume: ", lotSize);
                                tradeCountToday++;
                                Save_Day_Trade_Count_From_File(tradeCountToday);
                            }
                            else
                            {
                                Print("Failed to open Buy position");
                            }
                        }
                        else
                        {
                            Print("Failed to open Buy position, AMPM < ", Active_AMPM);
                            AMPM_BUY =0;
                        }
                    }
                }
                else if (lparam == 50) // اگر Control+2 فشرده شده باشد
                {
                    AMPM_SELL = CalculateAveragePipMovement(AMPM, false);

                    Read_Day_Trade_Count_From_File();

                    if (tradeCountToday >= MaxDailyTrades)
                    {
                        Print("Your trading limit for today has been exceeded!");
                        return ;
                    }
                    else
                    {
                        if(AMPM_SELL>=Active_AMPM)
                        {
                            if (trade.Sell(lotSize))
                            {
                                Print("Sell position opened with volume: ", lotSize);
                                tradeCountToday++;
                                Save_Day_Trade_Count_From_File(tradeCountToday);
                            }
                            else
                            {
                                Print("Failed to open Sell position");
                            } 
                        }
                        else
                        {
                            Print("Failed to open SELL position, AMPM < ", Active_AMPM);
                            AMPM_SELL =0;
                        }
                    }
                }
                else if (lparam == 48) // اگر Control+0 فشرده شده باشد
                {
                    if(PositionsTotal()>0)
                    {
                       for(int cnt = PositionsTotal()-1; cnt >= 0 && !IsStopped(); cnt-- )
                       {
                           if(PositionGetTicket(cnt))
                           {
                               trade.PositionClose(PositionGetInteger(POSITION_TICKET),100);
                               uint code = trade.ResultRetcode();
                               Print(IntegerToString(code));
                           }
                           
                       }
                    }
                    else
                    {
                        Print("NO Position For CLOSE Manually . . .");
                    }
                }
                else if (lparam == 51) // اگر Control+3 فشرده شده باشد
                {
                    if(PositionsTotal()>0)
                    {
                    
                       for(int cnt = PositionsTotal()-1; cnt >= 0 && !IsStopped(); cnt-- )
                       {
                           if(PositionGetTicket(cnt))
                           {
                               close_position_percentage(Parsall_manually);
                           }
                           
                       }
                    }
                    else
                    {
                        Print("NO Position For PARTIAL Manually . . .");
                    }  
                }
                else if (lparam == 53) // اگر Control+5 فشرده شده باشد
                {
                    if(PositionsTotal()>1)
                    {
                        EQ_OnBreakeven = true;
                    }
                    else if(PositionsTotal()==0)
                    {
                        Print("NO Position For EQ Break . . .");
                    }
                    else
                    {
                        Print("Currently, Only One Trade Is Active .\n *--> This Mode Requires At Least 2 Active Trades ..."); 
                    }  
                }
                else if (lparam == 54) // اگر Control+6 فشرده شده باشد
                {
                    if(PositionsTotal()>1)
                    {
                        if(EQ_OnBreakeven)
                        {
                            EQ_OnBreakeven = false;
                            VPT_c = 0.0 ;
                            buffer_c = 0.0 ;
                            Status_profit = 0.0;
                            Print("EQ-P Mode is DActive ...");
                        }
                        else
                        {
                            Print("Currently, EQ-P Mode is Not Active In Positions ...\n You Must First Activate EQ-P Mode,And Try Again ..."); 
                        }
                        
                    }
                    else if(PositionsTotal()==0)
                    {
                        Print("NO Position For EQ Break . . .");
                    }
                    else
                    {
                        Print("Currently, Only One Trade Is Active .\n *--> This Mode Requires At Least 2 Active Trades ..."); 
                    }
                }
            }
        }
    }
}



// تابع شروع اکسپرت
int OnInit()
{
    CreateVolumeInputPanel(); // ایجاد پنجره ورودی حجم بزرگ‌تر
    Read_Day_Trade_Count_From_File();
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert OnInit function                                           |
//+------------------------------------------------------------------+
// تابع پایان اکسپرت
void OnDeinit(const int reason)
{
       OnTimer(); 
       
    // پاک کردن فیلد ورودی و عنوان ایجاد شده
    ObjectDelete(0, "VolumeInput");
    ObjectDelete(0, "VolumeTitle");
    
}



//+------------------------------------------------------------------+
//| Decrypt a license using a key                                    |
//+------------------------------------------------------------------+
string DecryptLicense(string license_input, string key)
{
    uchar key_32[32];
    StringToCharArray(key, key_32);

    uchar source[], decrypted[];
    ArrayResize(source, StringLen(license_input) / 2);
    HexToArray(license_input, source);
    ResetLastError();
    if (CryptDecode(CRYPT_AES256, source, key_32, decrypted) == 0) 
    {
        Print("ERROR [CODE:", GetLastError(), "]");
        //WriteLog("ERROR [CODE:"+ IntegerToString(GetLastError())+ "]");
        return "";
    }
    return CharArrayToString(decrypted);
}

//+------------------------------------------------------------------+
//| Split the decrypted license string                               |
//+------------------------------------------------------------------+
bool SplitLicenseString(string decoded)
{
    string sep = "-";
    ushort u_sep = StringGetCharacter(sep, 0);
    string result[];
    int count = StringSplit(decoded, u_sep, result);

    if (count < 9) // تعداد مورد انتظار برای لایسنس شما
    {
        Print("لایسنس شما معتبر نمی باشد - خطای TTSB213014000 ");
        //WriteLog("لایسنس شما معتبر نمی باشد - خطای TTSB213014000 ");
        return false;
    }

    decrypted_username = result[0];
    decrypted_password = result[1];
    string years = result[2];
    string mount = result[3];
    string day = result[4];
    string hours = result[5];
    string minits = result[6];
    decrypted_active_code = result[7];
    decrypted_Account_login_number = result[8];

    decrypted_end_time = years + "." + mount + "." + day + " " + hours + ":" + minits;
    
    return true;
}


//+------------------------------------------------------------------+
//| Validate the license                                             |
//+------------------------------------------------------------------+
int ValidateLicense(string username_input, string password_input, string active_code_input)
{
    if (username_input != decrypted_username)
    {
        username_check_statuss = false;
        Print("نام کاربری وارد شده با لایسنس شما مطابقت ندارد ، لطفا نام کاریری را به صورت صحیح وارد کنید");
        //WriteLog("نام کاربری وارد شده با لایسنس شما مطابقت ندارد ، لطفا نام کاریری را به صورت صحیح وارد کنید");
        return -2;
    }

    if (password_input != decrypted_password)
    {
        password_check_statuss = false;
        Print("پسورد وارد شده با لایسنس شما مطابقت ندارد ، لطفا پسورد را به صورت صحیح وارد کنید");
        //WriteLog("پسورد وارد شده با لایسنس شما مطابقت ندارد ، لطفا پسورد را به صورت صحیح وارد کنید");
        return -3;
    }

    if (active_code_input != decrypted_active_code)
    {
        account_check_statuss = false;
         Print("خطای فعالسازی = 213/24/4006");
         //WriteLog("خطای فعالسازی = 213/24/4006");
        return -4;
    }

    long account_login_from_server = AccountInfoInteger(ACCOUNT_LOGIN);
    long decrypted_account_login_int = StringToInteger(decrypted_Account_login_number);

    if (account_login_from_server != decrypted_account_login_int)
    {
        account_check_statuss = false;
        Print("این لایسنس مربوط به این حساب کاربری نمی باشد ، لطفا بر روی حساب کاربری معتبر ربات را اجرا کنید");
        //WriteLog("این لایسنس مربوط به این حساب کاربری نمی باشد ، لطفا بر روی حساب کاربری معتبر ربات را اجرا کنید");
        return -5;
    }

    datetime license_expiry_date = StringToTime(decrypted_end_time);
    if (TimeCurrent() > license_expiry_date)
    {
        license_statuss = false;
        Print("تاریخ استفاده از لایسنس به اتمام رسیده است ، لطفا جهت دریافت لایسنس با پشتیبانی تماس بگیرید");
         //WriteLog("تاریخ استفاده از لایسنس به اتمام رسیده است ، لطفا جهت دریافت لایسنس با پشتیبانی تماس بگیرید");
        return -6;
    }

    username_check_statuss = true;
    password_check_statuss = true;
    account_check_statuss = true;
    license_statuss = true;

    return 1;
}

//+------------------------------------------------------------------+
//| HexToArray function                                              |
//+------------------------------------------------------------------+
void HexToArray(string str, uchar &arr[])
{
    uchar tc[];
    StringToCharArray(str, tc);
    int i = 0, j = 0;
    for (i = 0; i < StringLen(str); i += 2)
    {
        uchar tmpchr = (HEXCHAR_TO_DECCHAR(tc[i]) << 4) + HEXCHAR_TO_DECCHAR(tc[i + 1]);
        arr[j] = tmpchr;
        j++;
    }
}

//+------------------------------------------------------------------+
//| OnTimer function                                                 |
//+------------------------------------------------------------------+
void OnTimer()
{
    string decrypted_license = DecryptLicense(license_input_from_user, encryption_key);
    if (decrypted_license == "")
    {
        Print("لاینسس ربات وارد نشده است ، لطغا لایسنس خود را وارد کنید");
        Print("خطای با شماره TTSB213014001، لطفا در صورت نیاز با پشتیبانی تماس بگیرید");
        //WriteLog("لاینسس ربات وارد نشده است ، لطغا لایسنس خود را وارد کنید");
        //WriteLog("خطای با شماره TTSB213014001، لطفا در صورت نیاز با پشتیبانی تماس بگیرید");
        ExpertRemove(); // Remove the expert
        return;
    }

    if (!SplitLicenseString(decrypted_license))
    {
        //Print("License splitting failed");
        Print("خطای با شماره TTSB213014002، لطفا در صورت نیاز با پشتیبانی تماس بگیرید");
        //WriteLog("خطای با شماره TTSB213014002، لطفا در صورت نیاز با پشتیبانی تماس بگیرید");
        ExpertRemove(); // Remove the expert
        return;
    }

    int validation_result = ValidateLicense(username_input_from_user, password_input_from_user, active_code);

    if (validation_result != 1)
    {
       // Print("License validation failed with error code: ", validation_result);
        Print("خطای با شماره TTSB213014003",validation_result,"، لطفا در صورت نیاز با پشتیبانی تماس بگیرید");
        //WriteLog("خطای با شماره TTSB213014003"+IntegerToString(validation_result)+"، لطفا در صورت نیاز با پشتیبانی تماس بگیرید");
        ExpertRemove(); // Remove the expert
        return;
    }

    if(Bot_RUN)
    {
        Print("ربات در حال اجراست ...");
        Bot_RUN = false;
    }
    
   // WriteLog("ربات در حال اجراست ...");

   // به‌روزرسانی مستطیل‌ها هر بار که تایمر فعال می‌شود
    //Initializ_FVG(30);
    // ادامه فرآیندها
}

//+------------------------------------------------------------------+
//| Function to check license expiration                             |
//+------------------------------------------------------------------+
void CheckLicenseExpiration()
{
    // تبدیل تاریخ انقضای لایسنس به datetime
    datetime licenseExpiration = StringToTime(decrypted_end_time);

    // دریافت زمان فعلی
    datetime currentTime = TimeCurrent();

    int total_position = PositionsTotal();

    // بررسی آیا معامله‌ای باز است یا خیر
    if (total_position > 0)
    {
        // در اینجا منتظر بمانید تا همه معاملات بسته شوند
        while (PositionsTotal() > 0)
            Sleep(1000); // صبر برای بسته شدن معاملات
    }

    // بررسی آیا تاریخ انقضای لایسنس گذشته است یا خیر
    if (currentTime > licenseExpiration)
    {
        license_statuss = false;
        Print("تاریخ استفاده از لایسنس به اتمام رسیده است ، لطفا جهت دریافت لایسنس با پشتیبانی تماس بگیرید");
        //WriteLog("تاریخ استفاده از لایسنس به اتمام رسیده است ، لطفا جهت دریافت لایسنس با پشتیبانی تماس بگیرید");
        ExpertRemove();
    }
}


void Check_device_status()
{

    int fileHandle = FileOpen(filePath, FILE_READ|FILE_ANSI|FILE_TXT);
    
    if (fileHandle != INVALID_HANDLE)
    {
        string status = FileReadString(fileHandle);
        FileClose(fileHandle);
        
        if (status == "Status: Connected")
        {
            if (Device_stataus_show_message_connect)
            {
                Device_status = true;
                Print("Device Assistance Bot Connected");
                Device_stataus_show_message_connect = false;
                Device_stataus_show_message_disconnect = true;
            }
           
        }
        else if (status == "Status: Disconnected")
        {
            if (Device_stataus_show_message_disconnect)
            {
                Device_status = false;
                Print("Device Assistance Bot NOT Connected");
                Device_stataus_show_message_disconnect = false;
                Device_stataus_show_message_connect = true;
            }
           
        }
    }
    else
    {
        Print("Erorre: TADB/213025005"); // خطلا در خواندن فایل
    }
}


bool check_Run_paython_program()
{
// چک کردن وجود فایل
  if (FileIsExist(signalFilePath))
  {
    int fileHandle = FileOpen(signalFilePath, FILE_READ|FILE_ANSI|FILE_TXT);

    if (fileHandle != INVALID_HANDLE)
    {
        string status = FileReadString(fileHandle);
        FileClose(fileHandle);
            
        if (status == "RUNNING")
        {
            return true;
        }
        else 
        {
            return false;
        }
    }
    else
    {
      Print("Erorre: TADB/213025003"); // خطلا در خواندن فایل
      return false;
    }
   
   }
   else
   {
     Print("please Run Mapsim Device Setting APP..."); 
     return false;
   }

return false;
   
}


double Managment_volume()
{
    double volume = 0;
    double account_Balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double Total_risk = (risk/100);// Risk in Balance
    double Total_risk_in_Balance = account_Balance * Total_risk; // میزان ریسک 
    double total_risk_USD = 0;
    double Commision = 0;
    double pipvalue = PipValue();


    total_risk_USD = Total_risk_in_Balance-Commision;
    volume=(total_risk_USD)/((SL_Pips*pipvalue)); // MAX Volume in Account Balance
    // تنظیم حجم به یک رقم اعشار
    volume = NormalizeDouble(volume, 1);
    return volume;

   
}

double Managment_Target_Money(double Volume_local)
{
    double pipvalue = PipValue();
    double Money_Target=0;
    Money_Target = ((Volume_local * pipvalue)*SL_Pips) ;// Max Target Money R/R  = 1;
    
    return Money_Target;
}

/*
//+------------------------------------------------------------------+
//| Function to check if trading is allowed                          |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
    if(tradingAllowed == false)
      return tradingAllowed;
    else
    {
      Check_SL_Mountly_Loos_From_Deposit_USD();
    }
    
    return tradingAllowed;
}


//+------------------------------------------------------------------+
//| Function to update daily profit and loss                         |
//+------------------------------------------------------------------+
void Managment_Daily_Profit_Loss()
{  
    
    dailyProfit = 0; // Reset daily profit
    dailyLoss = 0;   // Reset daily loss 

    totaldailyProfitUSD =0;
    totaldailyLossUSD =0;
    datetime end = TimeCurrent(); 
    string sdate = TimeToString (TimeCurrent(), TIME_DATE); 
    datetime start = StringToTime(sdate); 

    HistorySelect(start,end); 
    int TotalDeals = HistoryDealsTotal(); 

    for(int i = 0; i < TotalDeals; i++) 
    { 
        ulong Ticket = HistoryDealGetTicket(i); 

        if(HistoryDealGetInteger(Ticket,DEAL_ENTRY) == DEAL_ENTRY_OUT) 
        { 
            double LatestProfit = HistoryDealGetDouble(Ticket, DEAL_PROFIT); 
            if (LatestProfit > 0)
            {     
                dailyProfit += LatestProfit; 
            }
            else
            {
                dailyLoss += MathAbs(LatestProfit);
            }
        } 
    } 

    // if(reset_totaldailyLossUSD)
    // {
    //     totaldailyLossUSD = 0;
    //     dailyLoss = 0;
    // }
    // if(reset_totaldailyProfitUSD)
    // {
    //     totaldailyProfitUSD =0;
    //     dailyProfit =0;
    // }
    
    
    // چک کردن اگر به حداکثر سود یا زیان روزانه رسیده‌ایم
    double maxDailyProfit = initialBalance * (MaxDailyProfitPercent / 100);
    
    string tmaxDailyProfitUSD = "بیشترین سود روزانه = "+ DoubleToString(MaxDailyProfitUSD);
   
    string sdailyProfit = "سود روزانه = "+ DoubleToString(dailyProfit);
    Print("مقدار سود امروز = ",dailyProfit);
   

    double maxDailyLoss = initialBalance * (MaxDailyLossPercent / 100);
    
    
    string tmaxDailyLossUSD = "بیشترین ضرر روزانه = "+ DoubleToString(Total_risk_in_Balance);
   

    string sdailyLoss = "ضرر روزانه = "+ DoubleToString(dailyLoss);
    Print("مقدار ضرر امروز = ",dailyLoss);
    
    
    
    totaldailyProfitUSD = dailyProfit - dailyLoss ; 
    
    totaldailyLossUSD = dailyLoss - dailyProfit ; 

    string stotaldailyProfitUSD = "مقدار سود روزانه = "+ DoubleToString(totaldailyProfitUSD);
    Print(stotaldailyProfitUSD);
    
    
    string stotaldailyLossUSD = "مقدار ضرر روزانه = "+ DoubleToString(totaldailyLossUSD);
    Print(stotaldailyLossUSD);
    
   
    if (usdORpercent)
    {
        
        if (totaldailyProfitUSD >= MaxDailyProfitUSD || totaldailyLossUSD >= Total_risk_in_Balance)
        {
            tradingAllowed = false; // توقف معاملات
            Print("ربات به دلیل رسیدن به حداکثر سود یا زیان روزانه متوقف شده است *** USD *** ");
            
            SaveDailyBalanceInfo_DB(totaldailyProfitUSD,totaldailyLossUSD);
        }
        else
        {
         tradingAllowed = true;
         SaveDailyBalanceInfo_DB(totaldailyProfitUSD,totaldailyLossUSD);
        }
    }
    else
    {
        if (dailyProfit >= maxDailyProfit || dailyLoss >= maxDailyLoss)
        {
            tradingAllowed = false; // توقف معاملات
            Print("ربات به دلیل رسیدن به حداکثر سود یا زیان روزانه متوقف شده است *** PERCENT *** ");
            
            SaveDailyBalanceInfo_DB(totaldailyProfitUSD,totaldailyLossUSD);
        }
        else
        {
         tradingAllowed = true;
         SaveDailyBalanceInfo_DB(totaldailyProfitUSD,totaldailyLossUSD);
        }
        
    }
}
*/
//+------------------------------------------------------------------+
//| Function to update daily Trade Count                             |
//+------------------------------------------------------------------+
// تابع برای بررسی و به‌روزرسانی تعداد تریدهای روزانه
void UpdateDailyTradeCount()
{
    MqlDateTime now;
    TimeToStruct(TimeCurrent(), now); // تبدیل زمان فعلی به ساختار تاریخ و زمان
    string todydate = IntegerToString(now.year)+"/"+IntegerToString(now.mon)+"/"+IntegerToString(now.day);

    
    //Print("todydate=", todydate);

    if (lastTradeDay != todydate) // بررسی تغییر روز
    {
        Print("Last Trade Date =", lastTradeDay);
        Print("Today Date =", todydate);
        tradeCountToday = 0;
        lastTradeDay = todydate; // ذخیره روز جدید
        Save_Day_Trade_Count_From_File(tradeCountToday);
        Print("Today ,Count Trade is Reset ...");
    }
    
}


int CalculateDailyTrades()
{

    //double account_Balance = AccountInfoDouble(ACCOUNT_BALANCE);

    // Print("account_Balance=", account_Balance);
    // Print("TP(pip)=", TP_Pips);
    // Print("SL(pip)=", SL_Pips);
    // Print("Risk%=", risk);


    double volume_ = Managment_volume();
    
    //Print("volume_=", volume_);

    double daily_target =  Managment_Target_Money(volume_);// تارگت روزانه
    
    //Print("daily_target=", daily_target);

    
    double pipvalue = PipValue();
    
    //Print("pipvalue=", pipvalue);

    // محاسبه مقدار دلاری سود هر ترید (با در نظر گرفتن پارشال)
   double pp1 = (percenteg_volume_parsal_1 / 100.0);
   double pp2 = (percenteg_volume_parsal_2 / 100.0);
   double pp3 = (percenteg_volume_parsal_3 / 100.0);


    // Print("pp1=",DoubleToString(pp1));
    // Print("pp2=",pp2);
    // Print("pp3=",pp3);

    double partial1_Volume = (volume_* pp1) ;

    double partial2_Volume = ((volume_- partial1_Volume)* pp2) ;

    double sum_p1_p2_Volume = partial2_Volume+partial1_Volume;

    double partial3_Volume = ((volume_ - sum_p1_p2_Volume )* pp3) ;

    double sum_p1_p2_p3_Volume = partial1_Volume+partial2_Volume+partial3_Volume;

    double TP_Volume = volume_-sum_p1_p2_p3_Volume ;


    Print("***********************************");
    Print(" ");
    Print("Partial1 Volume =",partial1_Volume);
    Print("Partial2 Volume =",partial2_Volume);
    Print("Partial3 Volume =",partial3_Volume);
    Print("TP Volume =",TP_Volume);
    Print(" ");
    Print("***********************************");
    Print(" ");
    Print(" ");


    double partial1_pip= (TP_Pips/ 4) ;
    double partial2_pip= (TP_Pips/ 4)+ partial1_pip ;
    double partial3_pip = (TP_Pips/ 4)+ partial2_pip ;
    double TP_pip = TP_Pips ;

    Print("###################################");
    Print(" ");
    Print("Partial1 In The pip = ",partial1_pip);
    Print("Partial2 In The pip = ",partial2_pip);
    Print("Partial3 In The pip = ",partial3_pip);
    Print("TP In The pip = ",TP_pip);
    Print(" ");
    Print("###################################");
    Print(" ");
    Print(" ");
    double partial1_Profit = ((partial1_pip * pipvalue) * partial1_Volume) ;
    double partial2_Profit = ((partial2_pip * pipvalue) * partial2_Volume) ;
    double partial3_Profit = ((partial3_pip * pipvalue) * partial3_Volume) ;
    double TP_Profit = ((TP_pip * pipvalue) * TP_Volume) ;



    Print("$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$");
    Print(" ");
    Print("Partial1_Profit = ",partial1_Profit);
    Print("Partial2_Profit = ",partial2_Profit);
    Print("Partial3_Profit = ",partial3_Profit);
    Print("TP Profit = ",TP_Profit);
    Print(" ");
    Print("$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$");
    Print(" ");
    Print(" ");


    double profit_per_trade = partial1_Profit + partial2_Profit + partial3_Profit+ TP_Profit; // مجموع سود هر ترید

    Print("+++++++++++++++++++++++++++++++++++");
    Print(" ");
    Print("Profit For Per Trade = ",profit_per_trade);
    Print(" ");
    Print("+++++++++++++++++++++++++++++++++++");
    Print(" ");
    Print(" ");

    int required_trades = (int)ceil(daily_target / profit_per_trade); // تعداد ترید مورد نیاز

    Print("__________________________________");
    Print(" ");
    Print("Count Required For  Trades = ",required_trades);
    Print(" ");
    Print("__________________________________");
    Print(" ");
    Print(" ");

    return required_trades;
}

void Read_Day_Trade_Count_From_File()
{
    ResetLastError();
    int fileHandle = FileOpen(filePath_Day_Trade_Count, FILE_READ|FILE_TXT);
    
    if (fileHandle != INVALID_HANDLE)
    {
        string line = FileReadString(fileHandle);  // خواندن کل خط
        FileClose(fileHandle);

        // تقسیم مقدار خوانده‌شده بر اساس فاصله
        string parts[];
        int numParts = StringSplit(line, ' ', parts); // تقسیم خط به آرایه

        if (numParts == 2) // باید 2 مقدار داشته باشیم: تاریخ و تعداد تریدها
        {
            string savedDate = parts[0];
            long day_trades_count = StringToInteger(parts[1]); // تبدیل مقدار دوم به عدد

            // دریافت تاریخ امروز
            MqlDateTime now;
            TimeToStruct(TimeCurrent(), now);
            string todayDate = IntegerToString(now.year) + "/" + IntegerToString(now.mon) + "/" + IntegerToString(now.day);

            // بررسی تغییر روز
            if (savedDate != todayDate) 
            {
                tradeCountToday = 0;
                lastTradeDay = todayDate;
                Save_Day_Trade_Count_From_File(tradeCountToday) ;
            }
            else
            {
                tradeCountToday = (int) day_trades_count;
                lastTradeDay = savedDate;
            }
        }
        else
        {
            // در صورت خواندن مقدار نامعتبر، مقدار پیش‌فرض تنظیم شود
            tradeCountToday = 0;
            MqlDateTime now;
            TimeToStruct(TimeCurrent(), now);
            lastTradeDay = IntegerToString(now.year) + "/" + IntegerToString(now.mon) + "/" + IntegerToString(now.day);
        }
    }
    else
    {
        Print("Error_ReadFile: TADB/213025006", GetLastError()); // خطا در خواندن فایل
        tradeCountToday = 0;
        MqlDateTime now;
        TimeToStruct(TimeCurrent(), now);
        lastTradeDay = IntegerToString(now.year) + "/" + IntegerToString(now.mon) + "/" + IntegerToString(now.day);
        Save_Day_Trade_Count_From_File(tradeCountToday) ;
    }
}

void Save_Day_Trade_Count_From_File(int count) 
{
    ResetLastError();
    int fileHandle = FileOpen(filePath_Day_Trade_Count, FILE_WRITE|FILE_TXT);
    string last_trade_day = lastTradeDay+" ";
    if (fileHandle != INVALID_HANDLE) 
    {
        FileWrite(fileHandle, last_trade_day, count); // ذخیره تاریخ و تعداد تریدها
        FileClose(fileHandle);
    } 
    else 
    {
        Print("Error_Write_file: TADB/213025006", GetLastError()); // خطا در ذخیره فایل
    }
}

//___________________________________________________________________________

// تابع برای بستن تمامی پوزیشن‌ها زمانی که سود/ضرر سر به سر شود
void ClosePositionsOnBreakeven()
{
    double totalProfit = 0.0;
    double totalVolume = 0.0;
    // VPT_c = 0.0 ;
    // buffer_c = 0.0 ;
    // Status_profit = 0.0;
    // محاسبه اسپرد به واحد دلاری با استفاده از PipValue
    long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);  // مقدار اسپرد در Points
    
    // بررسی تمامی پوزیشن‌ها
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);  // دریافت شناسه پوزیشن
        if (PositionSelectByTicket(ticket))
        {
            double positionProfit = PositionGetDouble(POSITION_PROFIT);  // سود/ضرر پوزیشن
            totalProfit += positionProfit;  // افزودن سود/ضرر به مجموع کل
            double positionVolume = PositionGetDouble(POSITION_VOLUME);  // دریافت حجم پوزیشن
            totalVolume += positionVolume;  // افزودن حجم پوزیشن به مجموع
        }
    }
    totalProfit = NormalizeDouble(totalProfit, 2);
    totalVolume = NormalizeDouble(totalVolume, 2);

    double spreadAllowanceInDollar = (spreadPoints / pip_value_contract) * PipValue() * totalVolume;  
    spreadAllowanceInDollar = NormalizeDouble(spreadAllowanceInDollar, 2);

    double buffer = User_Bufer_Spread * spreadAllowanceInDollar;  // دو برابر اسپرد برای جلوگیری از تغییرات ناگهانی
    buffer = NormalizeDouble(buffer, 2);

    VPT_c = totalVolume;
    buffer_c = buffer;
    Status_profit = totalProfit;

    // Print("totalProfit = ",totalProfit);
    // Print("totalVolume = ",totalVolume);
    // Print("spreadAllowanceInDollar = ",spreadAllowanceInDollar);
    // Print("buffer = ",buffer);

    // اگر مجموع سود و ضرر برابر یا بیشتر از صفر به علاوه با مقداری buffer باشد، پوزیشن‌ها بسته می‌شوند
    if (totalProfit >= buffer)
    {
        for(int cnt = PositionsTotal()-1; cnt >= 0 && !IsStopped(); cnt-- )
        {
            if(PositionGetTicket(cnt))
            {
                trade.PositionClose(PositionGetInteger(POSITION_TICKET),100);
                uint code = trade.ResultRetcode();
                Print(IntegerToString(code));
            }
            
        }
        EQ_OnBreakeven = false;
        VPT_c = 0.0 ;
        buffer_c = 0.0 ;
        Status_profit = 0.0;
    }
}
//___________________________________________________________________________


void DrawDailyHighLow()
{
   // نام آبجکت‌ها برای مدیریت حذف و رسم مجدد
   string highLineName = "Daily_High_Line";
   string lowLineName = "Daily_Low_Line";
   
   // اگر نمایش غیر فعال شده است، خطوط را حذف کن
   if (!show_daily_high_low)
   {
      ObjectDelete(0,highLineName);
      ObjectDelete(0,lowLineName);
      return;
   }
   
   // دریافت مقدار High و Low روزانه
   double dailyHigh = iHigh(_Symbol, PERIOD_D1, 0);
   double dailyLow = iLow(_Symbol, PERIOD_D1, 0);
   
   // بررسی و حذف خطوط قبلی اگر وجود دارند
   ObjectDelete(0,highLineName);
   ObjectDelete(0,lowLineName);
   
   // رسم خط High روزانه
   ObjectCreate(0, highLineName, OBJ_HLINE, 0, 0, dailyHigh);
   ObjectSetInteger(0, highLineName, OBJPROP_COLOR, highLine_Color);
   ObjectSetInteger(0, highLineName, OBJPROP_STYLE, highLine_Style);
   ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, highLine_Width); // افزایش ضخامت خط
   
   // رسم خط Low روزانه
   ObjectCreate(0, lowLineName, OBJ_HLINE, 0, 0, dailyLow);
   ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, lowLine_Color);
   ObjectSetInteger(0, lowLineName, OBJPROP_STYLE, lowLine_Style);
   ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, lowLine_Width); // افزایش ضخامت خط
}

// دریافت اطلاعات کندل‌ها و ذخیره در آرایه
void Get_candel_OHLC(Candle_Stick &candleArray[], int numCandles)
{
    ArrayResize(candleArray, numCandles); // تنظیم اندازه آرایه

    for (int i = 0; i < numCandles; i++)
    {
        double openPrice = iOpen(NULL, 0, i);
        double closePrice = iClose(NULL, 0, i);
        double highPrice = iHigh(NULL, 0, i);
        double lowPrice = iLow(NULL, 0, i);

        string candleType;
        if (closePrice > openPrice)
            candleType = "Bullish"; // کندل صعودی
        else if (closePrice < openPrice)
            candleType = "Bearish"; // کندل نزولی
        else
            candleType = "Neutral"; // کندل خنثی

        // ذخیره اطلاعات کندل در ساختار
        candleArray[i].open_candel = openPrice;
        candleArray[i].close_candel = closePrice;
        candleArray[i].high_candel = highPrice;
        candleArray[i].low_candel = lowPrice;
        candleArray[i].type_candel = candleType;
    }

    // تغییر کندل‌های خنثی به نوع کندل قبلی
    for (int i = 1; i < numCandles; i++)
    {
        if (candleArray[i].type_candel == "Neutral")
            candleArray[i].type_candel = candleArray[i + 1].type_candel;
    }
}

// تابع برای رسم یا به‌روزرسانی خط
void DrawOrUpdateLine(string name, datetime time1, double price1, datetime time2, double price2, color clr ,ENUM_LINE_STYLE  line_OB_Style, int line_OB_Width)
{
    // فقط یک خط افقی برای قیمت ثابت
    ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price1); // خط افقی در سطح قیمت مشخص
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, line_OB_Style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, line_OB_Width);
}
void DrawOrUpdate_Midel_Shadow_Line(string name, datetime time1, double price1, datetime time2, double price2, color clr ,ENUM_LINE_STYLE  Mid_line_OB_Style, int Mid_line_OB_Width)
{
    // فقط یک خط افقی برای قیمت ثابت
    ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price1); // خط افقی در سطح قیمت مشخص
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, Mid_line_OB_Style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, Mid_line_OB_Width);
}

void check_Pivot_period()
{
    // آرایه‌هایی برای ذخیره موقعیت کندل‌ها
    double Max_Price_pivot_60[];
    double Min_Price_pivot_60[];

    //-----------------------------------
    double Temp_Max_Price_pivot_60[];
    double Temp_Min_Price_pivot_60[];

    int Pivot_Kaf_60 = 0;
    double kaf_Pivot_60[];

    int Pivot_saghf_60 = 0;
    double saghf_Pivot_60[];

    int kafhaye_payentar_60 = 0;
    int kafhaye_balatar_60 = 0;
    int kafhaye_range_60 = 0;
    int saghfaye_payentar_60 = 0;
    int saghfaye_balatar_60 = 0;
    int saghfaye_range_60 = 0;

    // // دریافت زمان‌های کندل‌ها
    // datetime timeArray[];
    // CopyTime(Symbol(), Period(), 0, 60, timeArray);

    double Positive_OB_midel_shadow = 0.0;

    // تشخیص کف و سقف‌ها و ذخیره قیمت آن‌ها برای 60 کندل آخر
    for (int i = 1; i < (Num_candels_period - 1); i++)  // Avoiding first and last candles to prevent out of bounds
    {
        // تشخیص کف pivot
        if((candel_last60[i].type_candel == "Bearish" && candel_last60[i+1].type_candel == "Bearish" && candel_last60[i-1].type_candel == "Bullish" && candel_last60[i].low_candel <= candel_last60[i-1].low_candel && candel_last60[i].low_candel <= candel_last60[i+1].low_candel) || (candel_last60[i].type_candel == "Bearish" && candel_last60[i+1].type_candel == "Bullish" && candel_last60[i-1].type_candel == "Bullish" ) || (candel_last60[i].type_candel == "Bearish" && candel_last60[i+1].type_candel == "Bullish" && candel_last60[i-1].type_candel == "Bullish") || (candel_last60[i].type_candel == "Bullish" && candel_last60[i+1].type_candel == "Bearish" && candel_last60[i].type_candel == "Bearish" &&(candel_last60[i].low_candel <= candel_last60[i-1].low_candel && candel_last60[i].low_candel <= candel_last60[i+1].low_candel)) || (candel_last60[i].low_candel < candel_last60[i-1].low_candel && candel_last60[i].low_candel < candel_last60[i+1].low_candel))
        //if (candel_last60[i].low_candel <= candel_last60[i-1].low_candel && candel_last60[i].low_candel <= candel_last60[i+1].low_candel)
        {
            // بررسی اینکه آیا هیچ کندلی تا نقطه i کلوزش بالاتر از خط کف نباشد
            bool isValidKaf = true;
            
            if(candel_last60[i].type_candel == "Bearish")
            {
                for (int j = i-1; j > 0; j--)  // از کندل i به سمت کندل‌های قبلی
                {
                    if (candel_last60[j].close_candel < candel_last60[i-1].low_candel)
                    {
                        isValidKaf = false;
                        ObjectDelete(0, "KafLine" + IntegerToString(i));
                        break;
                    }
                }

                if(isValidKaf)
                {
                    // اگر کف قبلی متفاوت از کف جدید باشد، یک خط جدید رسم کنیم
                    if (lastKafPrice != candel_last60[i-1].low_candel || lastKafIndex != i )
                    {
                        lastKafPrice = candel_last60[i-1].low_candel;
                        lastKafIndex = i;

                        if(Show_line_OB_Negative)
                        {
                            // رسم خط کف Pivot
                            DrawOrUpdateLine("KafLine" + IntegerToString(i), iTime(NULL, 0, i-1), candel_last60[i-1].low_candel, iTime(NULL, 0, 0), candel_last60[i-1].low_candel, line_OB_Negative_Color , line_OB_Negative_Style , line_OB_Negative_Width);
                        }
                        else
                        {
                            ObjectDelete(0, "KafLine" + IntegerToString(i));
                        }
                        if(Show_Midel_of_shadow_OB_Negative)
                        {
                            Positive_OB_midel_shadow =(candel_last60[i-1].open_candel+candel_last60[i-1].low_candel)/2;
                            DrawOrUpdate_Midel_Shadow_Line("Midel_OB_Low" + IntegerToString(i), iTime(NULL, 0, i-1), Positive_OB_midel_shadow, iTime(NULL, 0, 0), Positive_OB_midel_shadow, Midel_of_shadow_OB_Negative_Color , Midel_of_shadow_OB_Negative_Style , Midel_of_shadow_OB_Negative_Width);
                        }
                        else
                        {
                            ObjectDelete(0, "Midel_OB_Low" + IntegerToString(i));
                        }
                    }
                }
                else
                {
                    // bool isValid_Deleviery_Prise_Kaf = true;

                    // for (int j = i-1; j > 0; j--)  // از کندل i به سمت کندل‌های قبلی
                    // {
                    //     if (candel_last60[j].high_candel >= candel_last60[i-1].low_candel)
                    //     {
                    //         isValid_Deleviery_Prise_Kaf = false;
                    //         break;
                    //     }
                    // }

                    // if(isValid_Deleviery_Prise_Kaf)
                    // {
                    //     if (ObjectGetInteger(0, "KafLine" + IntegerToString(i), OBJPROP_STYLE) != STYLE_DASH)
                    //     {
                    //         ObjectSetInteger(0, "KafLine" + IntegerToString(i), OBJPROP_STYLE, STYLE_DASH);
                            
                    //         ObjectSetInteger(0, "KafLine" + IntegerToString(i), OBJPROP_COLOR, clrRed);
                    //     }
                    // }
                    // else
                    // {
                       if(Show_line_OB_Negative)
                        {
                            ObjectDelete(0, "KafLine" + IntegerToString(i));
                        }
                        if(Show_Midel_of_shadow_OB_Negative)
                        {
                           ObjectDelete(0, "Midel_OB_Low" + IntegerToString(i));
                        }
                    //}
                }
            }
            else if(candel_last60[i].type_candel == "Bullish")
            {
                for (int j = i; j > 0; j--)  // از کندل i به سمت کندل‌های قبلی
                {
                    if (candel_last60[j].close_candel < candel_last60[i].low_candel)
                    {
                        ObjectDelete(0, "KafLine" + IntegerToString(i));
                        isValidKaf = false;
                        break;
                    }
                }

                if(isValidKaf)
                {
                    // اگر کف قبلی متفاوت از کف جدید باشد، یک خط جدید رسم کنیم
                    if (lastKafPrice != candel_last60[i].low_candel || lastKafIndex != i)
                    {
                        lastKafPrice = candel_last60[i].low_candel;
                        lastKafIndex = i;
                        
                        // رسم خط کف Pivot
                        if(Show_line_OB_Negative)
                        {
                            DrawOrUpdateLine("KafLine" + IntegerToString(i), iTime(NULL, 0, i), candel_last60[i].low_candel, iTime(NULL, 0, 0), candel_last60[i].low_candel, line_OB_Negative_Color , line_OB_Negative_Style , line_OB_Negative_Width);
                        }
                        else
                        {
                            ObjectDelete(0, "KafLine" + IntegerToString(i));
                        }
                        if(Show_Midel_of_shadow_OB_Negative)
                        {
                            Positive_OB_midel_shadow =(candel_last60[i].open_candel+candel_last60[i].low_candel)/2;
                            DrawOrUpdate_Midel_Shadow_Line("Midel_OB_Low" + IntegerToString(i), iTime(NULL, 0, i), Positive_OB_midel_shadow, iTime(NULL, 0, 0), Positive_OB_midel_shadow, Midel_of_shadow_OB_Negative_Color , Midel_of_shadow_OB_Negative_Style , Midel_of_shadow_OB_Negative_Width);
                        }
                        else
                        {
                            ObjectDelete(0, "Midel_OB_Low" + IntegerToString(i));
                        }
                    }  
                }
                else
                {
                    //  bool isValid_Deleviery_Prise_Kaf = true;

                    // for (int j = i-1; j > 0; j--)  // از کندل i به سمت کندل‌های قبلی
                    // {
                    //     if (candel_last60[j].high_candel >= candel_last60[i].low_candel)
                    //     {
                    //         isValid_Deleviery_Prise_Kaf = false;
                    //         break;
                    //     }
                    // }

                    // if(isValid_Deleviery_Prise_Kaf)
                    // {
                    //     if (ObjectGetInteger(0, "KafLine" + IntegerToString(i), OBJPROP_STYLE) != STYLE_DASH)
                    //     {
                    //         ObjectSetInteger(0, "KafLine" + IntegerToString(i), OBJPROP_STYLE, STYLE_DASH);
                            
                    //         ObjectSetInteger(0, "KafLine" + IntegerToString(i), OBJPROP_COLOR, clrRed);
                            
                    //     }
                    // }
                    // else
                    // {
                        if(Show_line_OB_Negative)
                        {
                            ObjectDelete(0, "KafLine" + IntegerToString(i));
                        }
                        if(Show_Midel_of_shadow_OB_Negative)
                        {
                           ObjectDelete(0, "Midel_OB_Low" + IntegerToString(i));
                        }
                        
                    //}
                }
            }
        }

        // تشخیص سقف pivot
        if((candel_last60[i].type_candel == "Bullish" && candel_last60[i+1].type_candel == "Bullish" && candel_last60[i-1].type_candel == "Bearish" && candel_last60[i].high_candel >= candel_last60[i-1].high_candel && candel_last60[i].high_candel >= candel_last60[i+1].high_candel) || (candel_last60[i].type_candel == "Bullish" && candel_last60[i+1].type_candel == "Bearish" && candel_last60[i-1].type_candel == "Bearish" ) || (candel_last60[i].type_candel == "Bearish" && candel_last60[i+1].type_candel == "Bullish" && candel_last60[i-1].type_candel == "Bearish" && candel_last60[i].high_candel >= candel_last60[i-1].high_candel && candel_last60[i].high_candel >= candel_last60[i+1].high_candel) || (candel_last60[i].high_candel > candel_last60[i-1].high_candel && candel_last60[i].high_candel > candel_last60[i+1].high_candel))
        //else if (candel_last60[i].high_candel >= candel_last60[i-1].high_candel && candel_last60[i].high_candel >= candel_last60[i+1].high_candel)
        {
            // بررسی اینکه آیا هیچ کندلی تا نقطه i کلوزش پایین‌تر از خط سقف نباشد
            bool isValidSaghf = true;

            if(candel_last60[i].type_candel == "Bullish")
            {
                for (int j = i; j > 0; j--)  // از کندل i به سمت کندل‌های قبلی
                {
                    if (candel_last60[j].close_candel > candel_last60[i-1].high_candel)
                    {
                        // اگر قیمت بسته شدن کندل j بالاتر از سقف i باشد، شرط برقرار نیست
                        ObjectDelete(0, "SaghfLine" + IntegerToString(i));
                        isValidSaghf = false;
                        break;
                    }
                }
                if (isValidSaghf)
                {
                    // اگر سقف قبلی متفاوت از سقف جدید باشد، یک خط جدید رسم کنیم
                    if (lastSaghfPrice != candel_last60[i-1].high_candel || lastSaghfIndex!= i)
                    {
                        lastSaghfPrice = candel_last60[i-1].high_candel;
                        lastSaghfIndex =i;

                        if(Show_line_OB_Positive)
                        {
                            // رسم خط سقف Pivot
                            DrawOrUpdateLine("SaghfLine" + IntegerToString(i), iTime(NULL, 0, i-1), candel_last60[i-1].high_candel, iTime(NULL, 0, 0), candel_last60[i-1].high_candel, line_OB_Positive_Color ,line_OB_Positive_Style , line_OB_Positive_Width);
                        }
                        else
                        {
                            ObjectDelete(0, "SaghfLine" + IntegerToString(i));
                        }
                        
                        if(Show_Midel_of_shadow_OB_Positive)
                        {
                            Positive_OB_midel_shadow =(candel_last60[i-1].open_candel+candel_last60[i-1].high_candel)/2;
                            DrawOrUpdate_Midel_Shadow_Line("Midel_OB_High" + IntegerToString(i), iTime(NULL, 0, i-1), Positive_OB_midel_shadow, iTime(NULL, 0, 0), Positive_OB_midel_shadow, Midel_of_shadow_OB_Positive_Color ,Midel_of_shadow_OB_Positive_Style , Midel_of_shadow_OB_Positive_Width );
                        }
                        else
                        {
                            ObjectDelete(0, "Midel_OB_High" + IntegerToString(i));
                        }
                    }
                }
                else
                {
                    // bool isValid_Deleviery_Prise_saghf = true;

                    // for (int j = i-1; j > 0; j--)  // از کندل i به سمت کندل‌های قبلی
                    // {
                    //     if (candel_last60[j].low_candel >= candel_last60[i-1].high_candel)
                    //     {
                    //         isValid_Deleviery_Prise_saghf = false;
                    //         break;
                    //     }
                    // }
                    // if(isValid_Deleviery_Prise_saghf)
                    // {
                    //     if (ObjectGetInteger(0, "SaghfLine" + IntegerToString(i), OBJPROP_STYLE) != STYLE_DASH)
                    //     {
                    //         ObjectSetInteger(0, "SaghfLine" + IntegerToString(i), OBJPROP_STYLE, STYLE_DASH);
                            
                    //         ObjectSetInteger(0, "SaghfLine" + IntegerToString(i), OBJPROP_COLOR, clrBlue);
                            
                    //     }

                    // }
                    // else
                    // {
                        if(Show_line_OB_Positive)
                        {
                            ObjectDelete(0, "SaghfLine" + IntegerToString(i));
                        }
                        if(Show_Midel_of_shadow_OB_Positive)
                        {
                            ObjectDelete(0, "Midel_OB_High" + IntegerToString(i));
                        }
                    //}
                }
            }
            else if(candel_last60[i].type_candel == "Bearish")
            {
                for (int j = i; j > 0; j--)  // از کندل i به سمت کندل‌های قبلی
                {
                    if (candel_last60[j].close_candel > candel_last60[i].high_candel)
                    {
                        // اگر قیمت بسته شدن کندل j بالاتر از سقف i باشد، شرط برقرار نیست
                        ObjectDelete(0, "SaghfLine" + IntegerToString(i));
                        isValidSaghf = false;
                        break;
                    }
                }
                if (isValidSaghf)
                {
                     // اگر سقف قبلی متفاوت از سقف جدید باشد، یک خط جدید رسم کنیم
                    if (lastSaghfPrice != candel_last60[i].high_candel || lastSaghfIndex!= i)
                    {
                        lastSaghfPrice = candel_last60[i].high_candel;

                        lastSaghfIndex = i;

                        if(Show_line_OB_Positive)
                        {
                            // رسم خط سقف Pivot
                            DrawOrUpdateLine("SaghfLine" + IntegerToString(i), iTime(NULL, 0, i), candel_last60[i].high_candel, iTime(NULL, 0, 0), candel_last60[i].high_candel, line_OB_Positive_Color ,line_OB_Positive_Style , line_OB_Positive_Width);
                        }
                        else
                        {
                            ObjectDelete(0, "SaghfLine" + IntegerToString(i));
                        }
                        if(Show_Midel_of_shadow_OB_Positive)
                        {
                            Positive_OB_midel_shadow = (candel_last60[i].open_candel+candel_last60[i].high_candel)/2;
                            DrawOrUpdate_Midel_Shadow_Line("Midel_OB_High" + IntegerToString(i), iTime(NULL, 0, i), Positive_OB_midel_shadow, iTime(NULL, 0, 0), Positive_OB_midel_shadow, Midel_of_shadow_OB_Positive_Color ,Midel_of_shadow_OB_Positive_Style , Midel_of_shadow_OB_Positive_Width );
                        }
                        else
                        {
                            ObjectDelete(0, "Midel_OB_High" + IntegerToString(i));
                        }
                    }
                }
                else
                {

                    // bool isValid_Deleviery_Prise_saghf = true;

                    // for (int j = i-1; j > 0; j--)  // از کندل i به سمت کندل‌های قبلی
                    // {
                    //     if (candel_last60[j].low_candel >= candel_last60[i].high_candel)
                    //     {
                    //         isValid_Deleviery_Prise_saghf = false;
                    //         break;
                    //     }
                    // }
                    // if(isValid_Deleviery_Prise_saghf)
                    // {
                    //     if (ObjectGetInteger(0, "SaghfLine" + IntegerToString(i), OBJPROP_STYLE) != STYLE_DASH)
                    //     {
                    //         ObjectSetInteger(0, "SaghfLine" + IntegerToString(i), OBJPROP_STYLE, STYLE_DASH);
                            
                    //         ObjectSetInteger(0, "SaghfLine" + IntegerToString(i), OBJPROP_COLOR, clrBlue);
                            
                    //     }

                    // }
                    // else
                    // {
                        if(Show_line_OB_Positive)
                        {
                            ObjectDelete(0, "SaghfLine" + IntegerToString(i));
                        }
                        if(Show_Midel_of_shadow_OB_Positive)
                        {
                            ObjectDelete(0, "Midel_OB_High" + IntegerToString(i));
                        }
                    //}
                }
            }
        }
    }
}

