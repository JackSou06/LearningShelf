Parent 與 child 各有自己的 fd table；繼承的 fd 指向相同 open-file entry，所以仍共享 offset。

本題 child 先讀取並結束，parent 用 wait 等待，才進行自己的 read。順序是題目的一部分，不能忽略。

若沒有這個同步順序，不能只憑程式碼的上下位置，假設 parent 或 child 一定先執行。此處只介紹 CH3 需要的 fork 概念。