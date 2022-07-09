library IEEE;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use ieee.STD_LOGIC_UNSIGNED.all;

entity SPI_Master is

port ( 	i_clk			:	in std_logic;		
		i_rst_n			:	in std_logic;		
		i_sel_mode      :   in std_logic;     -- spi(0) or quad spi(1)
		i_wrrd_signal:      in std_logic;     -- write(1) read(0) signal 
		i_Data_Length:      in std_logic_vector(7 downto 0); 
		
		i_CPOL			:	in std_logic;	

		i_SS_POL		:	in std_logic;	
		i_data_latch_edge_sel : in std_logic;  
		i_Master_Clock_SCK_Multiplier : in std_logic_vector(7 downto 0);
		
		o_MOSI			:	out std_logic_vector(32 downto 1);	
		i_MISO_DATA		:	in std_logic_vector(32 downto 1);			
		i_MISO_address  :	in std_logic_vector(32 downto 1); 
		o_SCK			: 	out std_logic;	
		o_SS_n			: 	out std_logic;			
		io0	:	inout std_logic;	
		io1	:	inout std_logic;
		io2	:	inout std_logic;
		io3	:	inout std_logic;		
		o_Rx_Data_Valid	:	out std_logic;	
        i_Tx_Data_Valid	:	in std_logic;		
        o_Chip_en : out std_logic;		
		o_Busy: 	out std_logic   
	  );			 
end SPI_Master;

architecture RTL of SPI_Master is

signal qipp: std_logic_vector(8 downto 1);                   --quad page program
signal fast_read_so: std_logic_vector(8 downto 1);           --fast read single output
signal fast_read_quad_op: std_logic_vector(8 downto 1);      --fast read quad output
signal sipp: std_logic_vector(8 downto 1);                   --single input page program
signal wren: std_logic_vector(8 downto 1);
signal wrsr: std_logic_vector(8 downto 1);


signal slot_counter : std_logic_vector(7 downto 0);
signal sck_multiplier : std_logic_vector(7 downto 0);
signal sck_multiplier_div_2 : std_logic_vector(7 downto 0);
signal sck_multiplier_div_2_del: std_logic_vector(7 downto 0);
signal slot_counter_del: std_logic_vector(7 downto 0);

signal sck_full_pulse : std_logic;
signal sck_full_pulse_del : std_logic;
signal sck_half_pulse : std_logic;
signal sck_half_pulse_del : std_logic;
  
signal selected_pulse	: std_logic;
signal selected_pulse_1	: std_logic;
signal miso_data_valid	: std_logic;
signal miso_data_valid_del	: std_logic;

signal port_n : std_logic;
signal sck_temp : std_logic;
signal busy  : std_logic;


signal data_reg_shift: std_logic_vector(32 downto 1);
signal address_reg_shift: std_logic_vector(32 downto 1);
signal rx_data_reg_shift: std_logic_vector(32 downto 1);
signal k: integer:= 32;


type Type_SPI_FSM_State is (idle, SPI_conv_s1, SPI_conv_s2_wait, SPI_conv_s2, SPI_conv_s3);   		
signal SPI_FSM_State : Type_SPI_FSM_State;
  
signal SPI_CS_n_int	: std_logic;
signal SCLK_cnt 	: std_logic_vector(6 downto 0);	
signal CLK_cnt 	    : std_logic_vector(8 downto 0);	

ATTRIBUTE syn_preserve :  boolean;
ATTRIBUTE syn_keep     :  boolean;
ATTRIBUTE syn_encoding :  string;
ATTRIBUTE syn_encoding OF SPI_FSM_State    : SIGNAL IS "safe,sequential";
ATTRIBUTE syn_keep     OF SPI_FSM_State    : SIGNAL IS TRUE;
ATTRIBUTE syn_preserve OF SPI_FSM_State    : SIGNAL IS TRUE; 

begin
sck_multiplier <= i_Master_Clock_SCK_Multiplier;
sck_multiplier_div_2 <= '0' & sck_multiplier(7 downto 1); 
slot_counter_del <= '0' & slot_counter(7 downto 1); 
sck_multiplier_div_2_del <= '0' & sck_multiplier_div_2(7 downto 1);
port_n <= not(i_rst_n);
o_busy <= busy;
o_Chip_en <= SPI_CS_n_int;
o_Rx_Data_Valid <= miso_data_valid_del;

process(i_clk, port_n)
begin
    if rising_edge(i_clk)then
         k <= k-1;
	end if;
end process;


process(i_clk, port_n)
begin
    if (port_n = '0')then
	    slot_counter <= (others => '0');
		sck_full_pulse <= '0';
		sck_half_pulse <= '0';
	elsif rising_edge(i_clk)then
		if slot_counter_del = sck_multiplier then
			slot_counter <= (others => '0');
			sck_full_pulse <= '1';
		else
			slot_counter <= slot_counter + '1';
			sck_full_pulse <= '0';
		end if;
		
		if slot_counter = sck_multiplier_div_2_del then ---------
			sck_half_pulse <= '1';
		else
			sck_half_pulse <= '0';
		end if;
	END IF;
end process;

process(i_clk, port_n)
begin
    if (port_n = '0')then
	     CLK_cnt<= "000000000";
	elsif rising_edge(i_clk)then	   
			 CLK_cnt <= CLK_cnt + '1';		
    end if;
end process;	

process(i_clk, port_n)
begin
    if (port_n = '0')then
	     sck_full_pulse_del <= '0';
	     sck_half_pulse_del <= '0';
	elsif rising_edge(i_clk)then
		 sck_half_pulse_del <= sck_half_pulse;
		 sck_full_pulse_del <= sck_full_pulse;
	END IF;
end process; 

process(i_clk, port_n)
begin
    if (port_n = '0')then
	    o_SS_n <= '0';
	elsif rising_edge(i_clk)then
		if (i_SS_POL = '1')then
			o_SS_n <= (not SPI_CS_n_int);
		else
			o_SS_n <= SPI_CS_n_int;
		end if ;
	END IF;
end process;

process(i_clk, port_n)
begin
    if (port_n = '0')then
	    sck_temp <= '0';
	elsif rising_edge(i_clk)then
		if (sck_half_pulse = '1')then
			sck_temp <= '1';
		elsif (sck_full_pulse = '1')then
			sck_temp <= '0';
		end if ;
	END IF;
end process; 		



SPI_IF_FSM : process (i_clk,port_n)
begin
	if(port_n = '0')then
		SPI_FSM_State	 <=	idle;
		SPI_CS_n_int	 <= '1'; 
		SCLK_cnt <= "0000000";
		o_SCK 			 <= '0';
		busy			 <= '0';
		miso_data_valid  <= '0';
		
		
	elsif(i_clk'EVENT AND i_clk = '1')then
		case SPI_FSM_State is 		
			when idle =>
				
				SPI_CS_n_int <= '1'; 
				miso_data_valid  <= '0';
				
				if (i_CPOL = '1')then
					o_SCK <= '1';
				
				end if;
				busy <= '0';
				if(i_Tx_Data_Valid = '1' ) then
					SPI_FSM_State <= SPI_conv_s1;
					SCLK_cnt <= "0000000";
					busy <= '1';
				end if;
			
			when SPI_conv_s1 =>  
				busy <= '1';
				if (i_CPOL = '1')then
					if(sck_half_pulse = '1') then	
						SPI_CS_n_int <= '0'; 
						SCLK_cnt <= "0000000";
						o_SCK <= '1';
						SPI_FSM_State <= SPI_conv_s2_wait;
					end if;	
				end if;
			
			when SPI_conv_s2_wait  =>  
				busy <= '1';
				if (i_CPOL = '1')then
					if(sck_full_pulse = '1') then	
						SPI_CS_n_int <= '0'; 
						SCLK_cnt <= "0000000";
						o_SCK <= '1';
						SPI_FSM_State <= SPI_conv_s2;
					end if;
				end if;
				
			when SPI_conv_s2 =>
				busy <= '1';
				miso_data_valid <= '0';
				o_SCK <= sck_temp;
				if (i_CPOL = '1')then
					if(sck_full_pulse = '1') then
						
						if(SCLK_cnt = i_Data_Length) then
							SPI_CS_n_int <= '1'; 
							SCLK_cnt <= "0000000";
							SPI_FSM_State <= SPI_conv_s3;
						else
							SPI_CS_n_int <= '0'; 
							SCLK_cnt <= SCLK_cnt + '1';
						end if;
					end if;			
				end if;

				
			when SPI_conv_s3 =>	
				if (i_CPOL = '1')then
					o_SCK <= '1';
				
				end if;
				busy <= '1';
				miso_data_valid <= '1';
				SPI_FSM_State <= idle;					

			when others =>
				SPI_FSM_State <= idle;
			end case;
end if;

end process;


selected_pulse <= sck_full_pulse_del when i_CPOL = '0' else
				  sck_half_pulse_del;
				  
selected_pulse_1 <= sck_half_pulse  when i_data_latch_edge_sel = '0' else
					sck_full_pulse ;
					
---------------------------------writing data to memory-------------------------------------------------------------		    

-- process (port_n, i_Clk)
    -- begin
		-- if (port_n = '0') then
			 -- data_reg_shift <= (others => '0');			 
		-- elsif rising_edge(i_clk)then		      
			     -- if ((selected_pulse_1 = '1') and (SPI_CS_n_int = '0'))then 				 
			
				         -- data_reg_shift(32 downto 1) <= i_MISO_DATA(32 downto 1);	 
				   
		         -- end if;        				 
		 -- end if;
-- end process;	


	 
-- process (port_n, i_Clk)
    -- begin
		-- if (port_n = '0') then
			-- address_reg_shift <= (others => '0');
		-- elsif rising_edge(i_clk)then
			-- if ((selected_pulse_1 = '1') and (SPI_CS_n_int = '0'))then	
	
				         -- address_reg_shift(32 downto 1) <=  i_MISO_address(32 downto 1);					 
	                 
			-- end if;
		-- end if;
-- end process;		 

-- process(i_clk, port_n)
-- begin
    -- if (port_n = '0')then
	    -- wren <= (others=>'0');	   			
	-- elsif rising_edge(i_clk)then	        
		-- wren(8)<= '0';
		-- wren(7)<= '0';
		-- wren(6)<= '0';
		-- wren(5)<= '0';
		-- wren(4)<= '0';
		-- wren(3)<= '1';
		-- wren(2)<= '1';
		-- wren(1)<= '0';	
     -- end if;
-- end process;
	 
-- process(i_clk, port_n)
-- begin
    -- if (port_n = '0')then
	    -- qipp <= (others=>'0');	   			
	-- elsif rising_edge(i_clk)then	        
		-- qipp(8)<= '0'; 
		-- qipp(7)<= '0';
		-- qipp(6)<= '1';
		-- qipp(5)<= '1';
		-- qipp(4)<= '0';
		-- qipp(3)<= '1';
		-- qipp(2)<= '0';
		-- qipp(1)<= '0';	
     -- end if;
-- end process;

-- process(i_clk, port_n)
-- begin
    -- if (port_n = '0')then
	    -- fast_read_so <= (others=>'0');	   			
	-- elsif rising_edge(i_clk)then	        
		-- fast_read_so(8)<= '0';
		-- fast_read_so(7)<= '0';
		-- fast_read_so(6)<= '0';
        -- fast_read_so(5)<= '0';
		-- fast_read_so(4)<= '1';
		-- fast_read_so(3)<= '1';
		-- fast_read_so(2)<= '0';
		-- fast_read_so(1)<= '0';	
     -- end if;
-- end process;

-- process(i_clk, port_n)
-- begin
    -- if (port_n = '0')then
	    -- fast_read_quad_op <= (others=>'0');	   			
	-- elsif rising_edge(i_clk)then	        
		-- fast_read_quad_op(8)<= '0';
		-- fast_read_quad_op(7)<= '1';
		-- fast_read_quad_op(6)<= '1';
		-- fast_read_quad_op(5)<= '0';
		-- fast_read_quad_op(4)<= '1';
		-- fast_read_quad_op(3)<= '1';
		-- fast_read_quad_op(2)<= '0';
		-- fast_read_quad_op(1)<= '0';	
     -- end if;
-- end process;

-- process(i_clk, port_n)
-- begin
    -- if (port_n = '0')then
	    -- sipp <= (others=>'0');	   			
	-- elsif rising_edge(i_clk)then	        
		-- sipp(8)<= '0'; 
		-- sipp(7)<= '0';
		-- sipp(6)<= '0';
		-- sipp(5)<= '1';
		-- sipp(4)<= '0';
		-- sipp(3)<= '0';
		-- sipp(2)<= '1';
		-- sipp(1)<= '0';	
     -- end if;
-- end process;

-- process(i_clk, port_n)
-- begin
    -- if (port_n = '0')then
	    -- wrsr <= (others=>'0');	   			
	-- elsif rising_edge(i_clk)then	        
		-- wrsr(8)<= '0'; 
		-- wrsr(7)<= '0';
		-- wrsr(6)<= '0';
		-- wrsr(5)<= '0';
		-- wrsr(4)<= '0';
		-- wrsr(3)<= '0';
		-- wrsr(2)<= '0';
		-- wrsr(1)<= '1';	
     -- end if;
-- end process;

process(i_clk, port_n)
begin
    if (port_n = '0')then
	    io0 <= '0';
		io1 <= '0';
		io2 <= '0';
		io3 <= '0';	
        data_reg_shift <= (others => '0');
        address_reg_shift <= (others => '0');		
	elsif rising_edge(i_clk)then			 
				 if(i_wrrd_signal = '1') then 
				     qipp(8 downto 1)<= "00110100"; 
                     wren(8 downto 1)<= "00000110";				     
					 sipp(8 downto 1)<="00010010";
					 wrsr(8 downto 1)<="00000001";
					 
				     if(CLK_cnt = "000000001") then		
                         if ((selected_pulse_1 = '1') and (SPI_CS_n_int = '0'))then 					 
				         data_reg_shift(32 downto 1) <= i_MISO_DATA(32 downto 1);
						 address_reg_shift(32 downto 1) <=  i_MISO_address(32 downto 1);	
						 end if;
					 end if;
                     if(i_sel_mode = '0') then					 
					     if(CLK_cnt = "000000010") then						     
				              
						      io0 <= wren(1);	
                              wren <= wren(1) & wren(8 downto 2);							  
							  io1 <= '0';
		                      io2 <= '0';
		                      io3 <= '0';
					     end if;
						 if(CLK_cnt = "000001010") then
						     
						      io0 <= wrsr(1);
							  wrsr<= wrsr(1) & wrsr(8 downto 2);
							 io1 <= '0';
		                     io2 <='0';
		                     io3 <= '0';
						end if;
						 if(CLK_cnt = "000010010") then
						     
						         io0 <= sipp(1);	
								sipp<= sipp(1) & sipp(8 downto 2);	 
							 io1 <= '0';
		                     io2 <= '0';
		                     io3 <= '0';
							 end if;
						 if(CLK_cnt = "000011010") then	
						      
						         io0 <= address_reg_shift(1);
								address_reg_shift<= address_reg_shift(1) & address_reg_shift(32 downto 2);
							 io1 <= '0';
		                     io2 <= '0';
		                     io3 <= '0';
						end if;
     					if(CLK_cnt = "000100010") then   
						         	 
						         io0 <= data_reg_shift(1) ;
								 data_reg_shift<= data_reg_shift(1) & data_reg_shift(32 downto 2);
                                  io1 <= '0';
		                          io2 <='0';
		                          io3 <= '0';                      		 
						 end if;
					
                     elsif (i_sel_mode = '1') then
					     if(CLK_cnt = "000000010") then
						     
						      io0 <= wren(1);	
                              					  							
							  io1 <= '0';
		                      io2 <= '0';
		                      io3 <= '0';
						end if;
						 if(CLK_cnt = "000001010") then
						     
						      io0 <= wrsr(1);
							   	
							  io1 <='0';
		                      io2 <= '0';
		                      io3 <= '0';
							  end if;
						 if(CLK_cnt = "000010010") then
						    
						     io0 <= qipp(1);
							 qipp<= qipp(1) & qipp(8 downto 2);
							 io1 <= '0';
		                     io2 <= '0';
		                     io3 <= '0';
							 end if;
						 if(CLK_cnt = "000011010") then	
						    
						     io0 <= address_reg_shift(1);
								
							 io1 <= '0';
		                     io2 <= '0';
		                     io3 <= '0'; 
                         end if;							  
                         if(CLK_cnt = "000100010") then	
                             io0 <= data_reg_shift(1);							 							     
							 io1 <= data_reg_shift(2);
		                     io2 <= data_reg_shift(3);
		                     io3 <= data_reg_shift(4);
							 end if;
						 if(CLK_cnt = "000100011") then	
                             io0 <= data_reg_shift(5);							 							     
							 io1 <= data_reg_shift(6);
		                     io2 <= data_reg_shift(7);
		                     io3 <= data_reg_shift(8);	
						 end if;
                         if(CLK_cnt = "000100100") then	
                             io0 <= data_reg_shift(9);							 							     
							 io1 <= data_reg_shift(10);
		                     io2 <= data_reg_shift(11);
		                     io3 <= data_reg_shift(12);	
							 end if;
                         if(CLK_cnt = "000100101") then	
                             io0 <= data_reg_shift(13);							 							     
							 io1 <= data_reg_shift(14);
		                     io2 <= data_reg_shift(15);
		                     io3 <= data_reg_shift(16);	
					     end if;
						 if(CLK_cnt = "000100110") then	
                             io0 <= data_reg_shift(17);							 							     
							 io1 <= data_reg_shift(18);
		                     io2 <= data_reg_shift(19);
		                     io3 <= data_reg_shift(20);	
						 end if;
                         if(CLK_cnt = "000100111") then	
                             io0 <= data_reg_shift(21);							 							     
							 io1 <= data_reg_shift(22);
		                     io2 <= data_reg_shift(23);
		                     io3 <= data_reg_shift(24);
						 end if; 
                         if(CLK_cnt = "000101000") then	
                             io0 <= data_reg_shift(25);							 							     
							 io1 <= data_reg_shift(26);
		                     io2 <= data_reg_shift(27);
		                     io3 <= data_reg_shift(28);	
						 end if;
                         if(CLK_cnt = "000101001") then	
                             io0 <= data_reg_shift(29);							 							     
							 io1 <= data_reg_shift(30);
		                     io2 <= data_reg_shift(31);
		                     io3 <= data_reg_shift(32);
						 end if;
                        				 
                         end if;    
                         
                         
	               elsif(i_wrrd_signal = '0') then 
		     fast_read_so(8 downto 1)<= "00001100";
			 fast_read_quad_op(8 downto 1)<="01101100";
			 wren(8 downto 1)<= "00000110";	
			 wrsr(8 downto 1)<="00000001";			 
		     if(CLK_cnt = "000000001") then		
                 if ((selected_pulse_1 = '1') and (SPI_CS_n_int = '0'))then 					 				   
				 address_reg_shift(32 downto 1) <=  i_MISO_address(32 downto 1);	
				 end if;        			 	
		     end if;
             if(i_sel_mode = '0') then        
                 if(CLK_cnt = "000000010") then
				     
				     io0 <= wren(1);	
					 
					
				end if;
				 if(CLK_cnt = "000001010") then				     
					 io0 <= wrsr(1);
 					 wrsr<= wrsr(1) & wrsr(8 downto 2);	 
					
				end if;
				 if(CLK_cnt = "000010010") then
				    
				     io0 <= fast_read_so(1);	 
					 fast_read_so<= fast_read_so(1) & fast_read_so(8 downto 2);
					 io1 <= '0';
		             io2 <= '0';
		             io3 <= '0';
				 end if;
				 if(CLK_cnt = "000011010") then
 				     
                     io0 <= address_reg_shift(1);
					 
                    
				 end if;
				                					 
	         elsif(i_sel_mode = '1') then   
				if(CLK_cnt = "000000010") then
				     
						      io0 <= wren(1);	
						
				 end if;
				 if(CLK_cnt = "000001010") then
				  
						      io0 <= wrsr(1);
				
				 end if;
				 if(CLK_cnt = "000010010") then
				      
					 io0 <= fast_read_quad_op(1);
					 fast_read_quad_op<= fast_read_quad_op(1) & fast_read_quad_op(8 downto 2);			  
					 io1 <= '0';
		             io2 <= '0';
		             io3 <='0';
				 end if;
				 
				 if(CLK_cnt = "000011010") then                    
						         io0 <= address_reg_shift(1);
					  address_reg_shift<= address_reg_shift(1) & address_reg_shift(32 downto 2);			 
			         
				 end if;
				   end if ;					
			 end if;
end process; 

----------------------------------------- reading data from memory------------------------------------------------

-- process(i_clk, port_n)
-- begin		
	-- if rising_edge(i_clk)then          		 
		--if(i_wrrd_signal = '0') then 
		  --   fast_read_so(8 downto 1)<= "00001100";
			-- fast_read_quad_op(8 downto 1)<="01101100";
			 -- wren(8 downto 1)<= "00000110";	
			 -- wrsr(8 downto 1)<="00000001";			 
		     -- if(CLK_cnt = "000000001") then		
                 -- if ((selected_pulse_1 = '1') and (SPI_CS_n_int = '0'))then 					 				   
				 -- address_reg_shift(32 downto 1) <=  i_MISO_address(32 downto 1);	
				 -- end if;        			 	
		     -- end if;
        --     if(i_sel_mode = '0') then        
          --       if(CLK_cnt = "000000010") then
				     
		--		     io0 <= wren(1);	
					 
					
		---		end if;
		--		 if(CLK_cnt = "000001010") then				     
		--			 io0 <= wrsr(1);
 					 -- wrsr<= wrsr(1) & wrsr(8 downto 2);	 
					
		--		end if;
		--		 if(CLK_cnt = "000010010") then
				    
		--		     io0 <= fast_read_so(1);	 
		--			 fast_read_so<= fast_read_so(1) & fast_read_so(8 downto 2);
					 -- io1 <= '0';
		             -- io2 <= '0';
		             -- io3 <= '0';
		---		 end if;
		--		 if(CLK_cnt = "000011010") then
 				     
               --      io0 <= address_reg_shift(1);
					 
                    
		--		 end if;
				                					 
	         --elsif(i_sel_mode = '1') then   
		--		if(CLK_cnt = "000000010") then
				     
		--				      io0 <= wren(1);	
						
		--		 end if;
		--		 if(CLK_cnt = "000001010") then
				  
		--				      io0 <= wrsr(1);
				
		--		 end if;
		--		 if(CLK_cnt = "000010010") then
				      
		--			 io0 <= fast_read_quad_op(1);
		--			 fast_read_quad_op<= fast_read_quad_op(1) & fast_read_quad_op(8 downto 2);			  
					 -- io1 <= '0';
		             -- io2 <= '0';
		             -- io3 <='0';
		--		 end if;
				 
		--		 if(CLK_cnt = "000011010") then                    
		--				         io0 <= address_reg_shift(1);
					  -- address_reg_shift<= address_reg_shift(1) & address_reg_shift(32 downto 2);			 
			         
		--		 end if;
        				 
	         -- end if ;        
         -- end if;	        	 		      	 				 			 	     
     -- end if;
-- end process;  

process(i_clk, port_n)
begin
    if (port_n = '0')then
	        miso_data_valid_del <= '0';		        
        	rx_data_reg_shift <= (others=>'0');		
            o_MOSI<= X"00000000";			
			
	elsif rising_edge(i_clk)then 
	if(i_wrrd_signal = '0') then   
        if ((selected_pulse = '1') and (SPI_CS_n_int = '0'))then	 
		 if (miso_data_valid = '1')then 
             if(i_sel_mode = '0') then        
                 if (CLK_cnt = "000100010") then 
				      
				     rx_data_reg_shift(32) <= io1;
					 rx_data_reg_shift<= rx_data_reg_shift(32) & rx_data_reg_shift(31 downto 1);
					 
                     end if;
				 	
				 end if;
             else
              	 
			     if (CLK_cnt = "000100010") then 
				      rx_data_reg_shift(32) <= io0;
					 rx_data_reg_shift<= rx_data_reg_shift(32) & rx_data_reg_shift(31 downto 1);
                 elsif(CLK_cnt = "000100011") then
                     rx_data_reg_shift(32) <= io1;
					 rx_data_reg_shift<= rx_data_reg_shift(32) & rx_data_reg_shift(31 downto 1);
                 elsif(CLK_cnt = "000100100") then
                      rx_data_reg_shift(32) <= io2;
					 rx_data_reg_shift<= rx_data_reg_shift(32) & rx_data_reg_shift(31 downto 1);
                 elsif(CLK_cnt = "000100101") then
                     rx_data_reg_shift(32) <= io3;
					 rx_data_reg_shift<= rx_data_reg_shift(32) & rx_data_reg_shift(31 downto 1);				 
                 end if;
				
		          
             end if;						             				 
	     end if ;
		 
  	 if ( k<33 and k>0) then
	 o_MOSI	<= rx_data_reg_shift;
	
     end if;	 
     miso_data_valid_del <= miso_data_valid;		 
     end if;
	 
	 end if;
	 	 
end process; 
end RTL;


