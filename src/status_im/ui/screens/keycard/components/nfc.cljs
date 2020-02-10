(ns status-im.ui.screens.keycard.components.nfc
  (:require [reagent.core :as reagent]
            [re-frame.core :as re-frame]
            [status-im.i18n :as i18n]
            [status-im.ui.components.react :as react]
            [status-im.ui.screens.keycard.components.animated-circles
             :refer [animated-circles]]
            [status-im.ui.components.colors :as colors]
            [status-im.ui.screens.keycard.components.description :as description]
            [status-im.ui.screens.keycard.components.turn-nfc :as turn-nfc]
            [status-im.ui.screens.keycard.components.style :as styles]))

(def state->strings {:init       {:title       "Looking for cards..."
                                  :description "Put the card to the back of your phone to continue"}
                     :awaiting   {:title       "Still looking..."
                                  :description "Try moving the card around to find the NFC reader on your device"}
                     :processing {:title       "Processing..."
                                  :description "Try keeping the card still"}
                     :connected  {:title       "Connected"
                                  :description "Try keeping the card still"}
                     :error      {:title       "Connection lost"
                                  :description "Connect the card again to continue"}
                     :success    {:title       "Success"
                                  :description "You may remove the card now"}})

(defn card-sync-flow []
  (let [state (reagent/atom nil)]
    (fn [{:keys [on-card-connected on-card-disconnected]}]
      [react/view {:style styles/container-style}
       [react/view {:height        200
                    :margin-bottom 20}
        [animated-circles {:state             state
                           :on-card-disconnected on-card-disconnected
                           :on-card-connected on-card-connected}]]
       [description/animated-description
        (get state->strings @state)]])))

(defn connect-keycard [{:keys [on-connect on-cancel on-disconnect]}]
  (fn []
    [react/view {:style {:flex            1
                         :align-items     :center
                         :justify-content :center}}
     (when on-cancel
       [react/touchable-highlight
        {:on-press on-cancel
         :style    {:position :absolute
                    :top      0
                    :right    0}}
        [react/text {:style {:line-height        22
                             :padding-horizontal 16
                             :color              colors/blue
                             :text-align         :center}}
         (i18n/label :t/cancel)]])
     (if @(re-frame/subscribe [:hardwallet/nfc-enabled?])
       [card-sync-flow {:on-card-disconnected
                        #(re-frame/dispatch [on-disconnect])
                        :on-card-connected
                        #(re-frame/dispatch [on-connect])}]
       [turn-nfc/turn-nfc-on])]))
