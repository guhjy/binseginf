## Synopsis: the functions defined here aim to streamline the process of
## producing p-values. The general structure is \code{obj<-bsFs(y, ...)}, then
## \code{obj<-test(obj)}, which appends (adds) the inference results to the same
## object.

##' Function generic for \code{test.OOO()} functions.
##' @export
addpv <- function(obj,...) UseMethod("addpv")

##' Conducts basic checks for addpv.bsfs()
checks_addpv_bsfs <- function(obj, type){
    assert_that(class(obj)=="bsfs")
    assert_that(is.null(obj$pvs))
    if(type=="addnoise"){
        assert_that(obj$noisy)
        assert_that(!is.null(obj$sigma.add))
    }
    if(!is.null(obj$sigma.add) & type=="plain"){
        stop("Original algorithm was run with additive noise! Can't do plain inference.")
    }
}

##' Appends the inference results to an object of class |bsFs|.
##' @param obj object of type bsFs.
##' @param loc only test locations in \code{loc}.
##' @param type One of \code{ c("plain", "addnoise")}. If equal to
##'     \code{"addnoise"}, then \code{sigma.add} needs to be
##'     provided. Currently, the polyhedron is not formed (due to memory
##'     concerns) but instead it uses the \code{type=pre-multiply} option.
##' @param sigma Noise level (standard deviation) of data.
##' @param sigma.add Additive noise. Defaults to NULL, in which case no additive
##'     noise randomization inference is done.
##' @param inference.type One of \code{c("rows","pre-multiply")}. Defaults to '
##'     \code{"rows"}. Use \code{"pre-multiply"} if the polyhedron is too big
##'     for memory.  (Warning: the rest is more of a note to self (Justin) than
##'     ' for users.). The use of \code{"pre-multiply"} was originally built for
##'     ' WBS. It actually prevents \code{polyhedra.wbsfs()} from having to form
##'     ' the entire WBS polyhedron in the first place. It also makes importance
##'     ' sampling faster the \code{type="rows"} option for WBS (thanks to
##'     manual ' speedups we've made), but slower for all other segmentation
##'     methods ' since there are no such manual tweaks for speedup. The most
##'     crucial ' difference for the user is perhaps that, when the size of the
##'     polyhedron ' is too big in memory, then this is a !necessity! as it
##'     circumvents ' having to actually form the polyhedron.
##' @param mn Original mean vector. This is purely for simulation purposes,
##'     along with the |only.test.nulls| option.
##' @param only.test.nulls If \code{TRUE}, only test the contrasts whose true
##'     mean is zero (i.e. the ones that constitute null tests).
##' @export
addpv.bsfs <- function(obj, loc=NULL, type=c("plain", "addnoise"), sigma,
                       sigma.add=NULL, declutter=FALSE, min.num.things=30,
                       max.numIS=2000, mn=NULL, only.test.nulls=FALSE,
                       bootsub=FALSE, nboot=10000,
                       v2=FALSE){

    ## Basic checks
    type = match.arg(type)
    checks_addpv_bsfs(obj, type)

    ## Form the test contrasts
    vlist <- make_all_segment_contrasts(obj)
    vlist <- filter_vlist(vlist, loc, only.test.nulls, mn)

    ## Obtain p-values
    if(type=="plain"){
        if(bootsub){
            poly.nonfudged = polyhedra(obj, y=obj$y)
            ## Experimental
            if(v2){
                numSteps = cv.bsfs(obj$y, 10) ## This is expensive!
                cv.obj = bsfs(y, numSteps=numSteps)
                adjustmean = get_piecewise_mean(obj$y, sort(abs(cv.obj$cp)))
            } else {
                adjustmean = mean(y)
            }
            pvs = poly_pval_bootsub_for_vlist(obj$y, poly.nonfudged$gamma,
                                              vlist, nboot, sigma, adjustmean)
        } else {
            pvs = sapply(vlist, function(v){
                poly_pval_premultiply(y=obj$y, v=v, obj=obj, sigma=sigma)
            })
        }
    } else if (type=="addnoise") {
        pvs = sapply(vlist, function(v){
            pv = randomize_addnoise(y=obj$y.orig, 
                                    v=v, sigma=sigma, numIS=10,
                                    sigma.add=sigma.add,
                                    orig.fudged.obj=obj,
                                    max.numIS=max.numIS,
                                    min.num.things=min.num.things,
                                    inference.type="pre-multiply",
                                    )$pv})
    } else {
        stop("|type| argument is wrong!")
    }

    ## Add the inference results to object
    obj$pvs = pvs
    obj$vlist = vlist
    if(!is.null(mn)){obj$means = sapply(vlist, function(v){ sum(v*mn) })}
    return(obj)
}


##' Appends the inference results to an object of class |bsFs|.
##' @param obj object of type bsFs
##' @param loc only test locations in \code{loc}.
##' @param type One of \code{ c("plain", "addnoise")}. If equal to
##'     \code{"addnoise"}, then \code{sigma.add} needs to be provided.
##' @param sigma Noise level (standard deviation) of data.
##' @param inference.type One of \code{c("pre-multiply")}. Defaults to '
##'     \code{"pre-multiply"}. Use \code{"pre-multiply"} if the polyhedron is
##'     too big for memory. There is really no reason to use \code{"rows"} in
##'     WBS.
##' @param mn original mean vector.
##' @export
addpv.wbsfs <- function(obj, loc=NULL, type=c("plain", "rand"), sigma,
                        declutter=FALSE, mn=NULL, min.num.things=30, sigma.add=NULL,
                        inference.type=c("pre-multiply","rows")){

    ## Basic checks
    assert_that(class(obj)=="wbsfs")
    assert_that(is.null(obj$pvs))
    type = match.arg(type)
    inference.type = match.arg(inference.type)
    if(!is.null(sigma.add)) warning("You provided |sigma.add| but this will not be used.")

    ## Form the test contrasts
    vlist <- make_all_segment_contrasts(obj)
    vlist <- filter_vlist(vlist, loc)

    ## Obtain p-value
    if(type=="plain"){
        pvs = sapply(vlist, function(v){
            pv = poly.pval2(y=obj$y, poly=polyhedra(obj=obj$gamma, u=obj$u), v=v, sigma=sigma, bits=5000)$pv
        })
    } else if (type=="rand") {

        vlist <- filter_vlist(make_all_segment_contrasts(obj), loc)

        ## Get the p-values
        pvs = sapply(vlist, function(v){
            pv = randomize_wbsfs(v=v, winning.wbs.obj=obj,
                                 sigma=sigma, numIS=10,
                                 cumsum.y=cumsum(obj$y),
                                 cumsum.v=cumsum(v), bits=2000,
                                 max.numIS=2000,
                                 inference.type=inference.type,
                                 min.num.things=min.num.things)$pv
        })

    } else {
        stop("|type| argument is wrong!")
    }

    ## Add to object
    obj$pvs = pvs
    obj$vlist = vlist
    if(!is.null(mn)){obj$means = sapply(vlist, function(v){ sum(v*mn) })}
    return(obj)
}


##' Appends the inference results to an object of class |bsFs|.
##' @param obj object of type bsFs
##' @param loc only test locations in \code{loc}.
##' @param type One of \code{ c("plain", "addnoise")}. If equal to
##'     \code{"addnoise"}, then \code{sigma.add} needs to be provided.
##' @param sigma Noise level (standard deviation) of data.
##' @param sigma.add Additive noise. Defaults to NULL, in which case no additive
##'     noise randomization inference is done.
##' @param inference.type One of \code{c("rows","pre-multiply")}. Defaults to '
##'     \code{"rows"}. Use \code{"pre-multiply"} if the polyhedron is too big
##'     for memory. 
##' @param mn original mean vector.
##' @export
addpv.cbsfs <- function(obj, loc=NULL, type=c("plain", "addnoise"), sigma,
                        sigma.add=NULL, declutter=FALSE, mn=NULL,
                        min.num.things=30, numIntervals=NULL,
                        inference.type = c("rows", "pre-multiply")){

    ## Basic checks
    assert_that(class(obj)=="cbsfs")
    assert_that(is.null(obj$pvs))
    type = match.arg(type)
    if(type=="addnoise"){
        assert_that(obj$noisy)
        assert_that(!is.null(obj$sigma.add))
    }
    if(!is.null(numIntervals)) warning("You provided |numIntervals| but this will not be used.")
    if(!is.null(obj$sigma.add) & type=="plain"){
        stop("Original algorithm was run with additive noise! Can't do plain inference.")
    }

    ## Form the test contrasts
    vlist <- make_all_segment_contrasts(obj)
    vlist <- filter_vlist(vlist, loc)

    ## Obtain p-values
    if(type=="plain"){
        poly.nonfudged = polyhedra(obj)
        pvs = sapply(vlist, function(v){
            pv = poly.pval2(y=obj$y, poly=poly.nonfudged, v=v, sigma=sigma, bits=5000)$pv
        })

    } else if (type=="addnoise") {
        poly.fudged = polyhedra(obj)
        pvs = sapply(vlist, function(v){
            pv = randomize_addnoise(y=obj$y, v=v, sigma=sigma, numIS=10,
                                    sigma.add=obj$sigma.add,
                                    orig.fudged.poly=poly.fudged, bits= 5000,
                                    max.numIS=2000,
                                    inference.type=inference.type,
                                    min.num.things=min.num.things)$pv})
    } else {
        stop("|type| argument is wrong!")
    }

    ## Add to object
    obj$pvs = pvs
    obj$vlist = vlist
    if(!is.null(mn)){obj$means = sapply(vlist, function(v){ sum(v*mn) })}
    return(obj)
}


##' Appends the inference results to an object created as a result of
##' \code{genlassoinf::dualpathSvd2()}. It is required that, when
##' \code{type=="addnoise"}, that the object is a result of running fused lasso
##' on a noise-added response. This is flagged by \code{obj$noisy}. When
##' information criteria stopping is involved, then only contrasts from the
##' stopped model are used.
##' @param obj object of |path| type.
##' @param loc only test locations in \code{loc}.
##' @param type One of \code{ c("plain", "addnoise")}. If equal to
##'     \code{"addnoise"}, then \code{sigma.add} needs to be provided.
##' @param sigma Noise level (standard deviation) of data.
##' @param sigma.add Additive noise. Defaults to NULL, in which case no additive
##'     noise randomization inference is done.
##' @param mn original mean vector.
## ' @param stoptime temporarary addition
##' @export
addpv.fl <- function(obj, loc=NULL, type=c("plain", "addnoise"), sigma,
                     sigma.add=NULL, declutter=FALSE, mn=NULL, numIntervals=NULL,
                     inference.type = c("rows", "pre-multiply")){
                     ## stoptime){

    ## Basic checks
    if(obj$ic.stop){assert_that(obj$ic_flag=="normal")}
    assert_that(is.null(obj$pvs))
    type = match.arg(type)
    if(type=="addnoise"){
        assert_that(!is.null(obj$noisy))
        assert_that(obj$noisy)
        assert_that(!is.null(obj$sigma.add))
    }
    if(!is.null(numIntervals)) warning("You provided |numIntervals| but this will not be used.")
    if(!is.null(obj$sigma.add) & type=="plain"){
        stop("Original algorithm was run with additive noise! Can't do plain inference.")
    }

    ## The number of algorithm steps to use
    numSteps = (if(obj$ic.stop)obj$stoptime + obj$consec else obj$numSteps )

    ## Get randomized p-value
    vlist <- make_all_segment_contrasts(obj, numSteps)
    ## vlist <- make_all_segment_contrasts(obj, stoptime) ## Temporary addition
    vlist <- filter_vlist(vlist, loc)

    ## Obtain p-values
    if(type=="plain"){
        poly.nonfudged = polyhedra.fl(obj, numSteps)
        ## poly.nonfudged = polyhedra.fl(obj, stoptime) ## Temporary addition
        poly.combined = combine(poly.nonfudged, obj$ic_poly)
        pvs = sapply(vlist, function(v){
            pv = poly.pval2(y=obj$y, poly=poly.combined, v=v, sigma=sigma, bits=5000)$pv
        })
    } else if (type=="addnoise") {
        poly.fudged = polyhedra(obj, numSteps)
        pvs = sapply(vlist, function(v){
            pv = randomize_addnoise(y=obj$y.orig, v=v, sigma=sigma, numIS=10,
                                    sigma.add=sigma.add,
                                    orig.fudged.poly=poly.fudged, bits= 5000,
                                    inference.type=inference.type,
                                    max.numIS=2000, min.num.things=30)$pv})
    } else {
        stop("|type| argument is wrong!")
    }

    ## Add pvalues before return
    obj$pvs = pvs
    obj$vlist = vlist
    if(!is.null(mn)){obj$means = sapply(vlist, function(v){ sum(v*mn) })}
    return(obj)
}

addpv_fl = addpv.fl

##' Helper to harvest polyhedra from FL object.
polyhedra.fl <- function(obj, numSteps=NULL, record.nrows=TRUE){
    if(is.null(numSteps)) numSteps = obj$maxsteps
    Gobj = genlassoinf::getGammat.naive(obj=obj, y=obj$y,
                                        condition.step=numSteps)
    
    ## Harvest number of rows per step
    if(record.nrows){
        nrow.by.step = obj$nkstep
    } else {
        nrow.by.step = NULL
    }

    poly = polyhedra(obj=Gobj$G, u=Gobj$u, nrow.by.step=nrow.by.step)
    return(poly)
}

polyhedra_fl = polyhedra.fl


##' Proprietary print object for |path| class object. This is temporary, and
##' assumes that fused lasso (and not a different form of generalized lasso) is
##' run.
print.fl <- function(obj){
    cat("Detected changepoints using FL with", obj$numSteps, "steps is",
        obj$cp * obj$cp.sign, fill=TRUE)
    if(!is.null(obj$pvs)){
        cat("Pvalues of", names(obj$pvs), "are", obj$pvs, fill=TRUE)
    }
}
