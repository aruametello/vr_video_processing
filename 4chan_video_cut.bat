@echo off
setlocal ENABLEDELAYEDEXPANSION
::
::  file: discord_video_cut.bat
::
::  Author: Aruã Metello - contact: aruametello@gmail.com
::
::  Descripton: 
::  uses ffmpeg to cut a video file to a mp4 h264 video, opus audio
::  file within the 8MB constraint that discord has.
::
:: -------------------------------------
rem fancy colors because to make readability somewhat better.
rem modified, original from here https://stackoverflow.com/questions/2048509/how-to-echo-with-different-colors-in-the-windows-command-line
set cRED=[31m
set cGREEN=[32m
set cYELLOW=[33m
set cCYAN=[36m
set fDEFAULT=[0m
set cUP1LINE=[1A
set fBOLD=[1A
set cDEFAULT=[0m
set cCOLUMN=[40G

set sWHITE=[90m
set sRED=[91m
set sGREEN=[92m
set sYELLOW=[93m
set sBLUE=[94m
set sMAGENTA=[95m
set sCYAN=[96m
set sWHITE=[97m


:start_over
set cdir=%cd%
set script_dir=%~dp0
cd /d !script_dir!

Title ### cut video into a 4chan friendly file ###
cls
echo %cCYAN%checking dependencies... 


rem starting state of the terminal colors
echo %cDEFAULT%


rem create the local temporary folder if needed
mkdir temporary_files >NUL 2>NUL
set avs_temp="temporary_files\avisynth_%random%%random%%random%%random%.avs"



set ffmpeg_prepend=-y -loglevel quiet -stats
set ffmpeg_decoder_opts=-c:v h264_cuvid
set ffmpeg_encoder_opts=-c:v h264_nvenc




call :test_thing "FFMPEG.exe available" "bin\ffmpeg -version" " * bin\ffmpeg.exe seems to be missing, download the zip at %url_ffmpeg% and copy the file bin\ffmpeg.exe to the bin folder of this script. %cd%"
if !error_test_thing!==1 call :fatal_error_pause

call :test_thing "FFPROBE.exe available" "bin\ffprobe -version" " * bin\ffprobe.exe seems to be missing, download the zip at %url_ffmpeg% and copy the file bin\ffprobe.exe to the bin folder of this script. %cd%"
if !error_test_thing!==1 call :fatal_error_pause


call :test_thing_optional "FFMPEG can use Nvidia h264 encoding" "bin\ffmpeg -y -f lavfi -i color=size=1280x720:rate=25:color=black -c:v h264_nvenc -t 2.0 -f null -" "Not required. This is only available on geforce GPUs and can speedup the process."
if !error_test_thing!==1 (
set ffmpeg_encoder_opts=-c:v libx264
set ffmpeg_decoder_opts=
)


set ffmpeg_encoder_opts=-c:v libvpx


rem call :test_thing "FFMPEG can use Nvidia h264 decoding" "bin\ffmpeg -y -c:v h264_cuvid -i ^"!mkv_temp!^" -c:v h264_nvenc -f null -" "Not required. This is only available on geforce GPUs and can speed up the process."
rem if !error_test_thing!==1 (
rem set ffmpeg_decoder_opts=
rem set nvidia_decoder=0
rem )




rem maybe the user will drag+drop the file onto the script file instead of the window?
if NOT "%~1"=="" (
	set input_motion="%~1"
	echo %cDEFAULT%
	echo Using "%~1" as the input file from the command line.
)else (
	:ask_input_again
	rem Pergunta pro usuario as opcoes a utilizar
	echo %cDEFAULT%
	echo # Type or drag and drop the input video file on this window to fill this field.
	set input_motion=
	set /P input_motion=%sWHITE%Input file name:%cDEFAULT%
	
	if "!input_motion!"=="" (
		echo %sRED%error:%sYellow% the input_motion field can not be blank.%cdefault%
		goto ask_input_again
	)else (	
		if NOT EXIST "!input_motion!" (
			echo %sRED%error:%sYellow% cant read !input_motion!, check if the path is correct.%cdefault%
			goto ask_input_again		
		)
	)	
)





rem check the source file

set input_has_audio=0
set input_has_video=0
set final_input_mapping=-i "!avs_temp!"
for /f "tokens=1* delims==" %%a in ('bin\ffprobe -v quiet -i !input_motion! -print_format ini -show_streams ^2^>^&1') do (
	rem echo %%a -- %%b

	if "%%a"=="r_frame_rate" for /f "tokens=1,2 delims=/" %%c in ("%%b") do (

	
		if "%%d"=="" (
			set /a ffprobe_r_frame_rate_100=^(%%c * 100^)
		)else (
			set /a ffprobe_r_frame_rate_100=^(%%c * 100^) / %%d
		)
	)
	if "%%a"=="codec_name" set ffprobe_codec_name=%%b
	if "%%a"=="codec_type" set ffprobe_codec_type=%%b
	if "%%a"=="width" set ffprobe_width=%%b
	if "%%a"=="height" set ffprobe_height=%%b
	if "%%a"=="codec_name" set ffprobe_codec_name=%%b

	if "%%a"=="bit_rate" set bitrate=%%b

	if "%%a"=="DURATION" set duration_in_secs=%%b


	if "%%a"=="duration" (
		set ffprobe_duration=%%b
		
		if "!ffprobe_codec_type!"=="audio" (
			set input_has_audio=1
			rem put the original untouched audio into the final file.
		)
		
		if "!ffprobe_codec_type!"=="video" (
			set ffprobe_video_bitrate=!bitrate!
			echo Bitrate: !ffprobe_video_bitrate!
		
		
			set input_has_video=1
			call :format_float !ffprobe_r_frame_rate_100!			
			echo %cCYAN%Input video format: %sYELLOW%!ffprobe_codec_name! !ffprobe_width!x!ffprobe_height!@!ffprobe_r_frame_rate_100!fps%cDEFAULT%
			
			
			rem warn if the input video stream format suck
			if NOT "!ffprobe_codec_name!"=="h264" (
				echo %sRED%Warning: %cYELLOW%the input video stream is not h264, decoding the input might be slower and wont use nvidia hardware acceleration.%cDEFAULT%
				set ffmpeg_decoder_opts=				
				set nvidia_decoder=0				
			)		
		)
	)
)

Echo ####### CARALHO ########

if "!duration_in_secs!"=="" (
	
	for /f "tokens=1 delims=:.\" %%a in ("!ffprobe_duration!") do set video_duration_secs=%%a
	set duration_print_format=!video_duration_secs!s
	

)else (
	for /f "tokens=1,2,3 delims=:.\" %%a in ("!duration_in_secs!") do (


		call :trim_zeroes %%a
		set r_a=!num_ret!
		call :trim_zeroes %%b
		set r_b=!num_ret!
		call :trim_zeroes %%c
		set r_c=!num_ret!
		
		set /a video_duration_secs=^( !r_a! * 3600 ^) + ^( !r_b! * 60 ^) + !r_c!	

		set duration_print_format=!video_duration_secs!s

	)
)



rem warn the user if the file is weird
if "!input_has_video!"=="0" echo %cRED%ERROR! input file has no video stream!%cDEFAULT% && call :fatal_error_pause
if "!input_has_audio!"=="0" echo %cRED%ERROR! input file has no audio stream!%cDEFAULT% && call :fatal_error_pause




rem read some filename for the output
echo.
echo Type the name of the output file (without extension) or leave blank to generate automatically a filename.
set /P output_motion=%sWhite%Output file name:%cdefault%


rem empty field = random file name
if "%output_motion%"=="" (
set output_motion=!cdir!\4chan_%random%.webm
)else (
set output_motion=!cdir!\!output_motion!.webm
)



rem ---------------------------------------------------
:ask_time
echo.
echo Your input video is !duration_print_format! long, the length of the output will reduce
echo the overall video quality, it often works best at 60 seconds or less.
echo.
echo # Input the start of the cut in the hh:mm:ss format or leave blank to use the whole video.
echo hh:mm:ss format like 01:10:12
set /p ts_start=%sWhite%Start timestamp:%cdefault%

if NOT "!ts_start!"=="" (

  for /f tokens^=1^,2^,3^ delims^=: %%a in ('echo !ts_start!') do (  
	call :trim_zeroes %%a
	set r_a=!num_ret!
	call :trim_zeroes %%b
	set r_b=!num_ret!
	call :trim_zeroes %%c
	set r_c=!num_ret!

	if "!r_c!"=="" (	
	if "!r_b!"=="" (	
	 set ts_start_secs=!r_a!
	) else (	  
	 set /a ts_start_secs=^( !r_a! * 60 ^) + !r_b!
	)	
	)else ( 
	 set /a ts_start_secs=^( !r_a! * 3600 ^) + ^( !r_b! * 60 ^) + !r_c!
	)   
  )
)else (
	rem user wants to use the whole file
	set ts_start_secs=0
	set duration_user=!video_duration_secs!
)



if NOT "!ts_start!"=="" (
	:ask_time_end
	echo.
	echo # Input the end of the cut in the hh:mm:ss format
	set /p ts_end=%sWhite%End timestamp:%cDEFAULT%
	if NOT "!ts_end!"=="" (
	 
	  for /f tokens^=1^,2^,3^ delims^=: %%a in ('echo !ts_end!') do (  
		call :trim_zeroes %%a
		set r_a=!num_ret!
		call :trim_zeroes %%b
		set r_b=!num_ret!
		call :trim_zeroes %%c
		set r_c=!num_ret!


		if "!r_c!"=="" (	
		if "!r_b!"=="" (	
		 set ts_end_secs=!r_a!
		) else (	  
		 set /a ts_end_secs=^( !r_a! * 60 ^) + !r_b!
		)	
		)else ( 
		 set /a ts_end_secs=^( !r_a! * 3600 ^) + ^( !r_b! * 60 ^) + !r_c!
		)   
	  )
	  
	  rem echo set /a duration_user=!ts_end_secs! - !ts_start_secs!
	  set /a duration_user=!ts_end_secs! - !ts_start_secs!

	  if !duration_user! LSS 0 (
	  echo.
	  echo ERROR: Check the timestamps, they seem invalid!
	  echo.
	  goto ask_time_end
	  )
	)
)




rem set ts_start_secs_cmdline=-ss !ts_start_secs!
rem set duration_user_cmdline=-t !duration_user!

rem ---------------------------------------------------
rem doing the 4chan constraints stuff


set target_size_kb=3072
set audio_kbit=0
set /a target_size_bytes=!target_size_kb! * 1024


set /a budget_kbits = ^( ^( !target_size_kb! * 8 ^) / !duration_user! ^)
set /a video_kbit = !budget_kbits! - !audio_kbit! - 10

rem a cap for video bitrate 
if !video_kbit! GTR 8000 set video_kbit=8000


:try_again

rem start with the original resolution, and then consider downsampling if
rem the target bitrate is too low
set max_x_res=!ffprobe_width!
if !video_kbit! LSS 6000 if !max_x_res! GTR 1440 set max_x_res=1440
if !video_kbit! LSS 4000 if !max_x_res! GTR 1280 set max_x_res=1280
if !video_kbit! LSS 2000 if !max_x_res! GTR 1024 set max_x_res=1024
if !video_kbit! LSS 960 if !max_x_res! GTR 800 set max_x_res=800
if !video_kbit! LSS 896 if !max_x_res! GTR 720 set max_x_res=720
if !video_kbit! LSS 768 if !max_x_res! GTR 640 set max_x_res=640
if !video_kbit! LSS 640 if !max_x_res! GTR 480 set max_x_res=480
rem really didnt felt inspired to put cool resolutions with the really low bitrate outputs,
rem the result will be a blurry mess anyway


rem the user is trying to send the lord of the rings trilogy into a 8mb file.
if !video_kbit! LSS 600 (
  echo.
  echo Sorry but !duration_user! seconds is too long to reasonably render in a !target_size_kb!kb file.
  echo try with a smaller duration, %cYELLOW%ideally with 60 seconds or less%cDEFAULT%.
  echo.
  goto :ask_time
)


echo.
echo Attemping to encode the output with !video_kbit!k video bitrate, !audio_kbit!k audio bitrate.



rem echo ffmpeg %ffmpeg_prepend% !ffmpeg_decoder_opts! -ss !ts_start_secs_cmdline! -i !input_motion! -t !duration_user_cmdline! !ffmpeg_encoder_opts! -b:v !video_kbit!k -c:a libopus -b:a !audio_kbit!k %ffmpeg_video_filter% -preset slow "!output_motion!"
bin\ffmpeg %ffmpeg_prepend% !ffmpeg_decoder_opts! -ss !ts_start_secs! -i !input_motion! -t !duration_user! !ffmpeg_encoder_opts! -b:v !video_kbit!k -an -vf scale=!max_x_res!:-1 -preset slow "!output_motion!"
if ERRORLEVEL 1 echo fatal ffmpeg error! && call :fatal_error_pause



rem verificar o tamanho do arquivo de saida se tivemos sucesso ou falha
set output_bytes=99999999
for %%a in ("!output_motion!") do set output_bytes=%%~za
echo output size in bytes: !output_bytes!

rem for %%a in ("!output_motion!") do echo set output_bytes=%%a %%~za
rem pause

if !output_bytes! GTR !target_size_bytes! (
echo File exceeded target size with bitrate !video_kbit!k, trying again with a lower value
del "!output_motion!" >NUL 2>NUL
echo.
set /a video_kbit=!video_kbit! - 100
goto try_again
)else (
echo.
echo %cGREEN%Success: %cDEFAULT%!output_motion!
)




::aguardar 3 segundos
timeout 3 /nobreak >NUL 2>NUL
goto :eof



:: end of the main function
::================================================================
::================================================================
:: other functions and weird stuff
::================================================================
::================================================================

:fatal_error_pause
pause
exit
goto :eof

::================================================================
:test_thing
echo %cDEFAULT%%~1 %cCOLUMN%%cYELLOW%[...]
%~2 >NUL 2>NUL
if ERRORLEVEL 1 (
echo %cUP1LINE%%cDEFAULT%%~1 %cCOLUMN%%cRED%[FAIL]    
echo %cDEFAULT% %~3
set error_test_thing=1
exit /B
)else (
echo %cUP1LINE%%cDEFAULT%%~1 %cCOLUMN%%cGREEN%[OK]    
set error_test_thing=0

)
goto :eof

::================================================================
:test_thing_optional
echo %cDEFAULT%%~1 %cCOLUMN%%cYELLOW%[...]
%~2 >NUL 2>NUL
if ERRORLEVEL 1 (
echo %cUP1LINE%%cDEFAULT%%~1 %cCOLUMN%%cYELLOW%[not available]
echo %cDEFAULT% %~3
set error_test_thing=1
exit /B
)else (
echo %cUP1LINE%%cDEFAULT%%~1 %cCOLUMN%%cGREEN%[OK]    
set error_test_thing=0
)
goto :eof

::================================================================
:format_float
set /a ff_a=%1 / 100
set /a ff_b=%1 %% 100
set ret_float=!ff_a!.!ff_b!
goto :eof


::===================================================================
:trim_zeroes
set num_ret=%1
 :loop_trim_zeroes 
 if "!num_ret!"=="0" (
 goto :eof
 )

 if "%num_ret:~0,1%"=="0" (
 set num_ret=%num_ret:~1,999%
 
  
 goto loop_trim_zeroes
 )
goto :eof

