{-
 
  Copyright 2022-23, Juspay India Pvt Ltd
 
  This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License
 
  as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program
 
  is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 
  or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of
 
  the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}

module Components.MobileNumberEditor.View where

import Prelude (Unit, ($), (<>), (==), (&&), not, negate, const, bind, pure, unit, map, (-), (+))
import Effect (Effect)
import Data.Maybe (Maybe(..))
import Engineering.Helpers.Commons (os)
import Components.MobileNumberEditor.Controller (Action(..), Config, listExpandingAnimationConfig, listClosingAnimationConfig)
import PrestoDOM (InputType(..),Gravity(..), Length(..), Orientation(..), PrestoDOM, Visibility(..), Margin(..), Padding(..), alpha, background, color, cornerRadius, editText, fontStyle, gravity, height, hint, hintColor, imageUrl, imageView, lineHeight, letterSpacing, linearLayout, margin, relativeLayout, scrollView, onClick, onChange, onAnimationEnd, orientation, padding, pattern, singleLine, stroke, text, textSize, textView, visibility, weight, width, id, inputType, multiLineEditText, maxLines, inputTypeI, onFocus, clickable, separator, separatorRepeat,imageWithFallback)
import Font.Style as FontStyle
import Common.Types.App
import PrestoDOM.Animation as PrestoAnim
import Styles.Colors as Color
import Helpers.Utils (getCommonAssetStoreLink)
import Engineering.Helpers.Commons as EHC
import Animation as Anim
import Animation.Config (AnimConfig, animConfig)
import Data.Array (mapWithIndex, length)
import Components.MobileNumberEditor.CountryCodeConfig (getCountryCodesObj)
import Effect.Aff (killFiber, launchAff, launchAff_)
import Engineering.Helpers.Commons (flowRunner, getWindowVariable, liftFlow)
import Types.App (defaultGlobalState, FlowBT, ScreenType(..)) 
import Engineering.Helpers.Utils (loaderText, toggleLoader)
import MerchantConfig.Utils (getMerchant, Merchant(..))

view :: forall w .  (Action  -> Effect Unit) -> Config -> PrestoDOM (Effect Unit) w
view push config = 
  relativeLayout[
    height WRAP_CONTENT
    ,width MATCH_PARENT
  ][
    linearLayout 
      [ width MATCH_PARENT
      , height WRAP_CONTENT
      , orientation VERTICAL
      , margin config.margin
      ][  topLabelView config
        , editTextLayout push config
        , errorLabelLayout config
        ]
    , if config.countryCodeField.countryCodeOptionExpended then countryCodeOptionView  push config else textView[height $ V 0]
  ]
      

topLabelView :: forall w . Config -> PrestoDOM (Effect Unit) w
topLabelView config = 
  textView $ 
    [ height WRAP_CONTENT
    , width WRAP_CONTENT
    , text config.topLabel.text
    , color config.topLabel.color
    , gravity config.topLabel.gravity
    , lineHeight "28"
    , singleLine true
    , margin config.topLabel.margin
    , alpha config.topLabel.alpha
    , visibility config.topLabel.visibility
    ] <> (FontStyle.getFontStyle config.topLabel.textStyle LanguageStyle)


editTextLayout :: forall w .  (Action  -> Effect Unit) -> Config -> PrestoDOM (Effect Unit) w
editTextLayout push config = 
  linearLayout
    [ height config.height
    , width config.width
    , background config.background
    , cornerRadius config.cornerRadius
    , gravity CENTER_VERTICAL
    , orientation HORIZONTAL
    ](  if config.showCountryCodeField then 
          [countryCodeCaptureView push config, editTextView push config] 
          else [editTextView push config])

countryCodeCaptureView :: forall w. (Action -> Effect Unit) -> Config -> PrestoDOM (Effect Unit) w
countryCodeCaptureView push config  =
  linearLayout
    [ 
      height config.countryCodeCaptureConfig.height
    , width config.countryCodeCaptureConfig.width
    , margin config.countryCodeCaptureConfig.margin
    , background config.countryCodeCaptureConfig.background
    , orientation HORIZONTAL
    , stroke if config.countryCodeField.countryCodeOptionExpended then config.focusedStroke else config.stroke 
    , gravity CENTER
    , cornerRadius config.countryCodeCaptureConfig.cornerRadius
    , onClick  push $ const $ (if not config.countryCodeField.countryCodeOptionExpended then  ShowOptions else CloseOptions)
    , clickable $ (getMerchant FunctionCall) == (YATRISATHI)
    ] $
    [ 
      textView $
        [ 
          text $ config.countryCodeField.countryCode
        , margin $ MarginRight 8
        , height WRAP_CONTENT
        , width WRAP_CONTENT
        , gravity CENTER
        , color Color.black800
        ] <> FontStyle.subHeading1 LanguageStyle
      , linearLayout
          [ height WRAP_CONTENT
          , width WRAP_CONTENT
          , gravity RIGHT
          , visibility if (getMerchant FunctionCall) == (YATRISATHI) then VISIBLE else GONE
          ]
          [ imageView
            [ imageWithFallback if config.countryCodeField.countryCodeOptionExpended then "ny_ic_chevron_up," <> (getCommonAssetStoreLink FunctionCall) <> "ny_ic_chevron_up.png" else "ny_ic_chevron_down," <> (getCommonAssetStoreLink FunctionCall) <> "ny_ic_chevron_down.png"
            , height $ V 24
            , width $ V 15
            ]
          ]
      ]
    
countryCodeOptionView :: forall w. (Action -> Effect Unit) -> Config -> PrestoDOM (Effect Unit) w
countryCodeOptionView push config =
  PrestoAnim.animationSet
  ([] <> if EHC.os == "IOS" then
        [Anim.fadeIn config.countryCodeField.countryCodeOptionExpended
        , Anim.fadeOut  (not config.countryCodeField.countryCodeOptionExpended)]
        else if config.countryCodeField.countryCodeOptionExpended then
          [Anim.listExpandingAnimation $  listExpandingAnimationConfig config] 
          else [Anim.listExpandingAnimation $  listClosingAnimationConfig config
               ,Anim.fadeOut true])
            $
  scrollView[
      height WRAP_CONTENT 
    , width MATCH_PARENT
    , margin config.countryCodeOptionConfig.margin
  ][
    linearLayout
      [ height config.countryCodeOptionConfig.height
      , width config.countryCodeOptionConfig.width
      , background config.countryCodeOptionConfig.background
      , orientation VERTICAL
      , stroke config.countryCodeOptionConfig.stroke
      , cornerRadius config.countryCodeOptionConfig.cornerRadius
      ]
      (mapWithIndex (\index item ->
        linearLayout
          [ height config.countryCodeOptionElementConfig.height
          , width config.countryCodeOptionElementConfig.width
          , onClick push $ const $ CountryCodeSelected item
          , orientation VERTICAL
          ]
          [ linearLayout
            [ height MATCH_PARENT
            , width MATCH_PARENT 
            ][textView $
              [ text item.countryCode
              , color config.countryCodeOptionElementConfig.leftTextColor
              , margin config.countryCodeOptionElementConfig.leftTextMargin
              ] <> FontStyle.paragraphText LanguageStyle
              ,linearLayout
                [ height WRAP_CONTENT
                , weight 1.0
                ][]
             , textView $
              [ text item.countryName
              , color config.countryCodeOptionElementConfig.rightTextColor
              , margin config.countryCodeOptionElementConfig.rightTextMargin
              ] <> FontStyle.paragraphText LanguageStyle
            ] 
          , linearLayout
            [ height config.countryCodeOptionElementConfig.lineHeight
            , width MATCH_PARENT
            , background config.countryCodeOptionElementConfig.lineColor
            , margin config.countryCodeOptionElementConfig.lineMargin
            , visibility if ((length getCountryCodesObj)-1) == index  && config.countryCodeOptionElementConfig.lineVisibility then GONE else VISIBLE 
            ][]
          ]
        )(getCountryCodesObj)
      )
  ]



editTextView :: forall w. (Action -> Effect Unit) -> Config -> PrestoDOM (Effect Unit) w 
editTextView push config = 
  (if( os == "IOS" && (not config.editText.singleLine )) then multiLineEditText else editText) 
  $ [ height config.height
  , width config.width
  , id config.id
  , weight 1.0
  , color config.editText.color
  , text config.editText.text
  , hint config.editText.placeholder
  , singleLine config.editText.singleLine
  , hintColor config.editText.placeholderColor
  , background config.background
  , padding config.editText.padding
  , onChange push $ TextChanged config.id
  , gravity config.editText.gravity
  , letterSpacing config.editText.letterSpacing
  , alpha config.editText.alpha
  , onFocus push $ FocusChanged
  , cornerRadius 8.0
  , stroke if config.showErrorLabel then config.warningStroke else if config.editText.focused then config.focusedStroke else config.stroke
  ] <> (FontStyle.getFontStyle config.editText.textStyle LanguageStyle)
    <> (case config.editText.pattern of 
        Just _pattern -> case config.type of 
                          "text" -> [pattern _pattern
                                    , inputType TypeText]
                          "number" -> [ pattern _pattern
                                      , inputType Numeric]
                          "password" -> [ pattern _pattern
                                      , inputType Password]
                          _    -> [pattern _pattern]
        Nothing -> case config.type of 
                          "text" -> [inputType TypeText]
                          "number" -> [inputType Numeric]
                          "password" -> [inputType Password]
                          _    -> []) 
  <> (if config.editText.capsLock then [inputTypeI 4097] else [])
  <> (if not config.editText.enabled then if os == "IOS" then [clickable false] else [inputTypeI 0] else[])
  <> (if config.editText.separator == "" then [] else [
    separator config.editText.separator
  , separatorRepeat config.editText.separatorRepeat
  ])

errorLabelLayout :: forall w . Config -> PrestoDOM (Effect Unit) w
errorLabelLayout config =
  linearLayout 
    [ height WRAP_CONTENT
    , width MATCH_PARENT
    , orientation HORIZONTAL
    , gravity CENTER_VERTICAL
    ][  imageView
        [ height config.errorImageConfig.height
        , width config.errorImageConfig.width
        , imageUrl config.errorImageConfig.imageUrl
        , margin config.errorImageConfig.margin
        , padding config.errorImageConfig.padding
        , visibility if config.showErrorImage then VISIBLE else GONE
        ]
      , textView $
        [ height WRAP_CONTENT
        , width WRAP_CONTENT
        , text config.errorLabel.text
        , color config.errorLabel.color
        , gravity config.errorLabel.gravity
        , margin config.errorLabel.margin
        , lineHeight "28"
        , singleLine true
        , visibility if config.showErrorLabel then VISIBLE else GONE
        , alpha config.errorLabel.alpha
        ] <> (FontStyle.getFontStyle config.errorLabel.textStyle LanguageStyle)
    ]