(ns status-im.ui.screens.keycard.components.description
  (:require [reagent.core :as reagent]
            [status-im.ui.components.animation :as animation]
            [status-im.ui.components.react :as react]
            [status-im.ui.screens.keycard.components.style :as styles]))

(defn animated-description []
  (let [current-text   (reagent/atom nil)
        animated-value (animation/create-value 0)]
    (fn [{:keys [title description]}]
      [react/animated-view {}
       [react/text {:style           styles/title-style
                    :number-of-lines 1}
        title]
       [react/text {:style           styles/helper-text-style
                    :number-of-lines 2}
        description]])))
